/**
 * API Client with JWT Bearer Token Injection and Auto-Refresh
 */

// Where the API lives. Empty in development (the Vite proxy forwards /api to Django);
// set VITE_API_URL=https://your-api-host when the website and the API are hosted separately.
const customOrigin = (typeof window !== 'undefined' ? localStorage.getItem('tuitiontrack_api_url') : '') || '';
let resolvedOrigin = (customOrigin || import.meta.env.VITE_API_URL || '').trim().replace(/\/+$/, '');
if (resolvedOrigin && !resolvedOrigin.startsWith('http://') && !resolvedOrigin.startsWith('https://')) {
  resolvedOrigin = `https://${resolvedOrigin}`;
}
export const API_ORIGIN = resolvedOrigin;
export const BASE_URL = `${API_ORIGIN}/api/v1`;

let _refreshPromise = null;

/**
 * Resolves media/image paths against API_ORIGIN when hosted on separate domains.
 */
export function getMediaUrl(url) {
  if (!url) return '';
  if (/^https?:\/\//i.test(url)) return url;
  if (url.startsWith('/')) {
    return `${API_ORIGIN}${url}`;
  }
  return url;
}

export async function apiRequest(endpoint, options = {}) {
  const url = `${BASE_URL}${endpoint}`;
  const token = localStorage.getItem('access_token');

  const headers = {
    ...options.headers,
  };

  if (!(options.body instanceof FormData)) {
    headers['Content-Type'] = 'application/json';
  }

  if (token) {
    headers['Authorization'] = `Bearer ${token}`;
  }

  const config = {
    ...options,
    headers,
  };

  let response = await fetch(url, config);

  // If token expired (401), attempt refresh once (single-flight for parallel 401s)
  if (response.status === 401 && localStorage.getItem('refresh_token')) {
    if (!_refreshPromise) {
      const refreshToken = localStorage.getItem('refresh_token');
      _refreshPromise = fetch(`${BASE_URL}/auth/token/refresh/`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ refresh: refreshToken }),
      }).then(async (refreshResp) => {
        if (refreshResp.ok) {
          const refreshData = await refreshResp.json();
          localStorage.setItem('access_token', refreshData.access);
          if (refreshData.refresh) localStorage.setItem('refresh_token', refreshData.refresh);
          return refreshData.access;
        }
        throw new Error('refresh failed');
      }).catch(() => {
        localStorage.removeItem('access_token');
        localStorage.removeItem('refresh_token');
        localStorage.removeItem('user_data');
        window.location.href = '/login';
        return null;
      }).finally(() => {
        // reset on next tick so concurrent callers share the same promise
        setTimeout(() => { _refreshPromise = null; }, 0);
      });
    }
    try {
      const newAccess = await _refreshPromise;
      if (newAccess) {
        headers['Authorization'] = `Bearer ${newAccess}`;
        response = await fetch(url, { ...config, headers });
      }
    } catch {
      // redirect already handled
    }
  }

  const contentType = response.headers.get('content-type');
  let data = null;
  if (contentType && contentType.includes('application/json')) {
    data = await response.json();
  } else {
    data = await response.text();
  }

  if (!response.ok) {
    // Flatten DRF field errors: {field: [msg]} -> "field: msg"
    let errorMsg = 'Request failed';
    if ([502, 503, 504].includes(response.status)) {
      // The dev proxy / gateway answered, but the API behind it did not.
      throw new Error('Cannot reach the server. Make sure the backend is running, then try again.');
    }
    if (data && typeof data === 'object') {
      if (data.error || data.detail || data.message) {
        errorMsg = data.error || data.detail || data.message;
      } else {
        const parts = [];
        for (const [k, v] of Object.entries(data)) {
          parts.push(`${k}: ${Array.isArray(v) ? v.join(', ') : v}`);
        }
        errorMsg = parts.join(' | ') || errorMsg;
      }
    } else if (response.status >= 500 || (typeof data === 'string' && /^\s*<(!doctype|html)/i.test(data))) {
      // A server crash returns an HTML error page; never show that to the user.
      errorMsg = 'Something went wrong on the server. Please try again.';
    } else if (typeof data === 'string' && data) {
      errorMsg = data;
    }
    throw new Error(errorMsg);
  }

  // Transparent pagination auto-accumulation for GET requests so lists never stop at page 1
  if (data && typeof data === 'object' && Array.isArray(data.results) && data.next && (!options.method || options.method === 'GET')) {
    try {
      const accumulated = [...data.results];
      let nextUrl = data.next;
      while (nextUrl) {
        // DRF returns an absolute URL built from the backend's host; keep only the
        // path so the request stays same-origin (through the dev proxy) and avoids CORS.
        const parsedNext = new URL(nextUrl, window.location.origin);
        const fetchUrl = `${API_ORIGIN}${parsedNext.pathname}${parsedNext.search}`;
        const nextResp = await fetch(fetchUrl, { ...config, headers });
        if (!nextResp.ok) break;
        const nextData = await nextResp.json();
        if (Array.isArray(nextData.results)) {
          accumulated.push(...nextData.results);
        }
        nextUrl = nextData.next;
      }
      data.results = accumulated;
      data.count = accumulated.length;
    } catch (pageErr) {
      console.warn('Pagination auto-accumulation warning:', pageErr);
    }
  }

  return data;
}

export async function fetchServerOffset() {
  try {
    const before = Date.now();
    const resp = await fetch(`${BASE_URL}/auth/me/`, { method: 'HEAD' });
    const dateHeader = resp.headers.get('date');
    if (!dateHeader) return 0;
    const serverMs = new Date(dateHeader).getTime();
    const after = Date.now();
    const rtt = (after - before) / 2;
    return serverMs + rtt - after;
  } catch {
    return 0;
  }
}

export const api = {
  // Auth & Discovery
  login: (credentials) => apiRequest('/auth/token/', { method: 'POST', body: JSON.stringify(credentials) }),
  registerTutor: (data) => apiRequest('/auth/register/', { method: 'POST', body: JSON.stringify(data) }),
  registerStudent: (data) => apiRequest('/auth/register/student/', { method: 'POST', body: JSON.stringify(data) }),
  getTutors: (search = '') => apiRequest(`/auth/tutors/${search ? `?search=${encodeURIComponent(search)}` : ''}`),
  getMe: () => apiRequest('/auth/me/'),
  updateMe: (data) => apiRequest('/auth/me/', { method: 'PATCH', body: JSON.stringify(data) }),
  // Changing the password signs every other device out; the server hands this one a new session.
  changePassword: async (currentPassword, newPassword) => {
    const data = await apiRequest('/auth/change-password/', {
      method: 'POST',
      body: JSON.stringify({ current_password: currentPassword, new_password: newPassword }),
    });
    if (data?.access) localStorage.setItem('access_token', data.access);
    if (data?.refresh) localStorage.setItem('refresh_token', data.refresh);
    return data;
  },
  // Revokes this device's session on the server. Never throws: signing out must always work locally.
  logout: async () => {
    const refresh = localStorage.getItem('refresh_token');
    if (!refresh) return;
    try {
      await fetch(`${BASE_URL}/auth/logout/`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ refresh }),
      });
    } catch {
      // offline: the token simply expires on its own
    }
  },
  requestPasswordReset: (identifier) => apiRequest('/auth/password-reset/', {
    method: 'POST',
    body: JSON.stringify({ identifier }),
  }),
  confirmPasswordReset: (uid, token, newPassword) => apiRequest('/auth/password-reset/confirm/', {
    method: 'POST',
    body: JSON.stringify({ uid, token, new_password: newPassword }),
  }),
  getNotifications: () => apiRequest('/notifications/'),

  // Students & Prospective Roster
  getStudents: () => apiRequest('/students/'),
  getUnassignedStudents: () => apiRequest('/students/unassigned/'),
  createStudent: (studentData) => apiRequest('/students/', { method: 'POST', body: JSON.stringify(studentData) }),
  getStudentDetail: (id) => apiRequest(`/students/${id}/`),
  updateStudent: (id, data) => apiRequest(`/students/${id}/`, { method: 'PATCH', body: JSON.stringify(data) }),
  toggleStudentActive: (id) => apiRequest(`/students/${id}/toggle_active/`, { method: 'POST' }),
  // Sets a new temporary password; the response is the only time it is ever shown.
  resetStudentPassword: (id) => apiRequest(`/students/${id}/reset_password/`, { method: 'POST' }),

  // Tuitions (Tuition-Centric Architecture)
  getTuitions: () => apiRequest('/tuitions/'),
  getTuitionDetail: (id) => apiRequest(`/tuitions/${id}/`),
  createTuition: (data) => apiRequest('/tuitions/', { method: 'POST', body: JSON.stringify(data) }),
  updateTuition: (id, data) => apiRequest(`/tuitions/${id}/`, { method: 'PATCH', body: JSON.stringify(data) }),
  deleteTuition: (id) => apiRequest(`/tuitions/${id}/`, { method: 'DELETE' }),
  enrollInTuition: (tuitionId, studentId) => apiRequest(`/tuitions/${tuitionId}/enroll/`, {
    method: 'POST',
    body: JSON.stringify({ student_id: studentId }),
  }),
  unenrollFromTuition: (tuitionId, studentId) => apiRequest(`/tuitions/${tuitionId}/unenroll/`, {
    method: 'POST',
    body: JSON.stringify({ student_id: studentId }),
  }),
  enrollManyInTuition: (tuitionId, studentIds) => apiRequest(`/tuitions/${tuitionId}/enroll/`, {
    method: 'POST',
    body: JSON.stringify({ student_ids: studentIds }),
  }),
  // Marks a class of the group's shared cycle; every enrolled student sees it.
  markTuitionClass: (tuitionId, classNo, completed, date = null, topic = '') => apiRequest(`/tuitions/${tuitionId}/mark_class/`, {
    method: 'PATCH',
    body: JSON.stringify({ class_no: classNo, completed, date, topic }),
  }),

  // Connection requests (student asks to join a tutor)
  getConnections: (status = '') => apiRequest(`/connections/${status ? `?status=${encodeURIComponent(status)}` : ''}`),
  sendConnectionRequest: (tutorId, message = '') => apiRequest('/connections/', {
    method: 'POST',
    body: JSON.stringify({ tutor_id: tutorId, message }),
  }),
  withdrawConnection: (id) => apiRequest(`/connections/${id}/`, { method: 'DELETE' }),
  acceptConnection: (id, tuitionId = null) => apiRequest(`/connections/${id}/accept/`, {
    method: 'POST',
    body: JSON.stringify(tuitionId ? { tuition_id: tuitionId } : {}),
  }),
  rejectConnection: (id) => apiRequest(`/connections/${id}/reject/`, { method: 'POST' }),

  // Legacy Tuition Batches (backward compatibility)
  getBatches: () => apiRequest('/batches/'),
  createBatch: (data) => apiRequest('/batches/', { method: 'POST', body: JSON.stringify(data) }),
  getBatchDetail: (id) => apiRequest(`/batches/${id}/`),
  updateBatch: (id, data) => apiRequest(`/batches/${id}/`, { method: 'PATCH', body: JSON.stringify(data) }),
  deleteBatch: (id) => apiRequest(`/batches/${id}/`, { method: 'DELETE' }),
  addStudentToBatch: (batchId, studentId) => apiRequest(`/batches/${batchId}/add_student/`, {
    method: 'POST',
    body: JSON.stringify({ student_id: studentId }),
  }),
  removeStudentFromBatch: (batchId, studentId) => apiRequest(`/batches/${batchId}/remove_student/`, {
    method: 'POST',
    body: JSON.stringify({ student_id: studentId }),
  }),

  // Attendance & Dynamic Cycles (Per-Tuition Engine)
  getAttendanceCycles: (arg1 = null, arg2 = null) => {
    const params = new URLSearchParams();
    if (typeof arg1 === 'object' && arg1 !== null) {
      const tId = arg1.tuition_id || arg1.tuition;
      const sId = arg1.student_id || arg1.student;
      if (tId && tId !== 'all') params.append('tuition_id', tId);
      if (sId) params.append('student_id', sId);
    } else {
      if (arg1 && arg1 !== 'all') params.append('tuition_id', arg1);
      if (arg2) params.append('student_id', arg2);
    }
    const query = params.toString() ? `?${params.toString()}` : '';
    return apiRequest(`/attendance-cycles/${query}`);
  },
  toggleAttendanceClass: (cycleId, classNo, completed, date = null, topic = '') => apiRequest(`/attendance-cycles/${cycleId}/toggle_class/`, {
    method: 'PATCH',
    body: JSON.stringify({ class_no: classNo, completed, date, topic }),
  }),
  resetAttendanceCycle: (cycleId) => apiRequest(`/attendance-cycles/${cycleId}/reset/`, { method: 'POST' }),

  // Legacy Cycles
  getCycles: (studentId) => apiRequest(`/cycles/${studentId ? `?student_id=${studentId}` : ''}`),
  getCycleDetail: (id) => apiRequest(`/cycles/${id}/`),
  toggleClass: (cycleId, classNo, completed, date = null, topic = '') => apiRequest(`/cycles/${cycleId}/toggle_class/`, {
    method: 'PATCH',
    body: JSON.stringify({ class_no: classNo, completed, date, topic }),
  }),
  resetCycle: (cycleId) => apiRequest(`/cycles/${cycleId}/reset/`, { method: 'POST' }),

  // Analytics
  getWalletAnalytics: () => apiRequest('/analytics/wallet/'),

  // Exams & Assignments
  getExams: (studentId = null, batchId = null, tuitionId = null) => {
    const params = new URLSearchParams();
    if (studentId) params.append('student_id', studentId);
    if (batchId) params.append('batch_id', batchId);
    if (tuitionId) params.append('tuition_id', tuitionId);
    const query = params.toString() ? `?${params.toString()}` : '';
    return apiRequest(`/exams/${query}`);
  },
  getExamDetail: (id) => apiRequest(`/exams/${id}/`),
  createExam: (examData) => apiRequest('/exams/', { method: 'POST', body: JSON.stringify(examData) }),
  updateExam: (id, examData) => apiRequest(`/exams/${id}/`, { method: 'PATCH', body: JSON.stringify(examData) }),
  deleteExam: (id) => apiRequest(`/exams/${id}/`, { method: 'DELETE' }),
  // Opens the exam for the student: starts their timer (timed exams) and returns the questions.
  startExam: (examId) => apiRequest(`/exams/${examId}/start/`, { method: 'POST' }),
  duplicateExam: (examId, tuitionId = null) => apiRequest(`/exams/${examId}/duplicate/`, {
    method: 'POST',
    body: JSON.stringify(tuitionId ? { tuition_id: tuitionId } : {}),
  }),
  getQuestionBank: (search = '') => apiRequest(`/exams/question_bank/${search ? `?search=${encodeURIComponent(search)}` : ''}`),
  getExamSubmissions: (examId) => apiRequest(`/exams/${examId}/submissions/`),
  submitExam: (examId, submissionData) => apiRequest(`/exams/${examId}/submit/`, {
    method: 'POST',
    body: JSON.stringify(submissionData),
  }),
  // Student: the evaluated paper, or {available: false} while results are pending.
  getExamResult: (examId) => apiRequest(`/exams/${examId}/result/`),
  // Tutor: publish results now (true) or take them back (false).
  publishExamResults: (examId, publish = true) => apiRequest(`/exams/${examId}/publish_results/`, {
    method: 'POST',
    body: JSON.stringify({ publish }),
  }),
  getExamLeaderboard: (examId) => apiRequest(`/exams/${examId}/leaderboard/`),
  gradeSubmission: (submissionId, gradeData) => apiRequest(`/submissions/${submissionId}/grade/`, {
    method: 'PATCH',
    body: JSON.stringify(gradeData),
  }),

  // Media
  uploadMedia: (formData) => apiRequest('/media/upload/', { method: 'POST', body: formData }),
  fetchServerOffset: () => fetchServerOffset(),

  // ── Tutor Code Connection (Student → Tutor invite-code flow) ──────────
  // Student enters a 6-char code to send a connection request to a tutor.
  connectByCode: (tutorCode, message = '') =>
    apiRequest('/connections/by-code/', {
      method: 'POST',
      body: JSON.stringify({ tutor_code: tutorCode.trim().toUpperCase(), message }),
    }),

  // ── Student Dashboard: Connected Tutors ───────────────────────────────
  // Returns tutors with accepted connection requests; each has display_name ("Ashraf Sir").
  getMyTutors: () => apiRequest('/my-tutors/'),
  // Detailed view of one tutor: routine + homework.
  getTutorDetail: (tutorId) => apiRequest(`/my-tutors/${tutorId}/`),

  // ── Homework ──────────────────────────────────────────────────────────
  getHomework: (params = {}) => {
    const query = new URLSearchParams();
    if (params.tutorId) query.append('tutor_id', params.tutorId);
    if (params.evaluated !== undefined) query.append('evaluated', params.evaluated);
    const qs = query.toString() ? `?${query.toString()}` : '';
    return apiRequest(`/homework/${qs}`);
  },
  getHomeworkDetail: (id) => apiRequest(`/homework/${id}/`),
  createHomework: (data) =>
    apiRequest('/homework/', { method: 'POST', body: JSON.stringify(data) }),
  updateHomework: (id, data) =>
    apiRequest(`/homework/${id}/`, { method: 'PATCH', body: JSON.stringify(data) }),
  deleteHomework: (id) => apiRequest(`/homework/${id}/`, { method: 'DELETE' }),
  // Tutor marks homework as evaluated/done. Optional {feedback: "..."} body.
  markHomeworkDone: (id, feedback = '') =>
    apiRequest(`/homework/${id}/mark_done/`, {
      method: 'POST',
      body: JSON.stringify({ feedback }),
    }),
  // Student submits an optional online URL as their submission.
  submitHomework: (id, url = '') =>
    apiRequest(`/homework/${id}/submit/`, {
      method: 'POST',
      body: JSON.stringify({ submitted_online_url: url }),
    }),
};
