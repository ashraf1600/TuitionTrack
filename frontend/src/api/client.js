/**
 * API Client with JWT Bearer Token Injection and Auto-Refresh
 */

const BASE_URL = '/api/v1';

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
        const fetchUrl = nextUrl.startsWith('http') ? nextUrl : `${BASE_URL}${nextUrl}`;
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

let _refreshPromise = null;

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

  // Students & Prospective Roster
  getStudents: () => apiRequest('/students/'),
  getUnassignedStudents: () => apiRequest('/students/unassigned/'),
  createStudent: (studentData) => apiRequest('/students/', { method: 'POST', body: JSON.stringify(studentData) }),
  getStudentDetail: (id) => apiRequest(`/students/${id}/`),
  updateStudent: (id, data) => apiRequest(`/students/${id}/`, { method: 'PATCH', body: JSON.stringify(data) }),
  toggleStudentActive: (id) => apiRequest(`/students/${id}/toggle_active/`, { method: 'POST' }),

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
  submitExam: (examId, submissionData) => apiRequest(`/exams/${examId}/submit/`, {
    method: 'POST',
    body: JSON.stringify(submissionData),
  }),
  getExamLeaderboard: (examId) => apiRequest(`/exams/${examId}/leaderboard/`),
  gradeSubmission: (submissionId, gradeData) => apiRequest(`/submissions/${submissionId}/grade/`, {
    method: 'PATCH',
    body: JSON.stringify(gradeData),
  }),

  // Media
  uploadMedia: (formData) => apiRequest('/media/upload/', { method: 'POST', body: formData }),
  fetchServerOffset: () => fetchServerOffset(),
};
