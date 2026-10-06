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

  // If token expired (401), attempt refresh once
  if (response.status === 401 && localStorage.getItem('refresh_token')) {
    const refreshToken = localStorage.getItem('refresh_token');
    try {
      const refreshResp = await fetch(`${BASE_URL}/auth/token/refresh/`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ refresh: refreshToken }),
      });

      if (refreshResp.ok) {
        const refreshData = await refreshResp.json();
        localStorage.setItem('access_token', refreshData.access);
        headers['Authorization'] = `Bearer ${refreshData.access}`;

        // Retry original request
        response = await fetch(url, { ...config, headers });
      } else {
        // Refresh token expired - clear and redirect
        localStorage.removeItem('access_token');
        localStorage.removeItem('refresh_token');
        localStorage.removeItem('user_data');
        window.location.href = '/login';
      }
    } catch {
      localStorage.removeItem('access_token');
      localStorage.removeItem('refresh_token');
      localStorage.removeItem('user_data');
      window.location.href = '/login';
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
    const errorMsg = data?.error || data?.detail || data?.message || (typeof data === 'object' ? JSON.stringify(data) : 'Request failed');
    throw new Error(errorMsg);
  }

  return data;
}

export const api = {
  // Auth
  login: (credentials) => apiRequest('/auth/token/', { method: 'POST', body: JSON.stringify(credentials) }),
  registerTutor: (data) => apiRequest('/auth/register/', { method: 'POST', body: JSON.stringify(data) }),
  registerStudent: (data) => apiRequest('/auth/register/student/', { method: 'POST', body: JSON.stringify(data) }),
  getMe: () => apiRequest('/auth/me/'),

  // Students
  getStudents: () => apiRequest('/students/'),
  createStudent: (studentData) => apiRequest('/students/', { method: 'POST', body: JSON.stringify(studentData) }),
  getStudentDetail: (id) => apiRequest(`/students/${id}/`),
  updateStudent: (id, data) => apiRequest(`/students/${id}/`, { method: 'PATCH', body: JSON.stringify(data) }),
  toggleStudentActive: (id) => apiRequest(`/students/${id}/toggle_active/`, { method: 'POST' }),

  // Tuition Batches
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

  // Cycles
  getCycles: (studentId) => apiRequest(`/cycles/${studentId ? `?student_id=${studentId}` : ''}`),
  getCycleDetail: (id) => apiRequest(`/cycles/${id}/`),
  toggleClass: (cycleId, classNo, completed) => apiRequest(`/cycles/${cycleId}/toggle_class/`, {
    method: 'PATCH',
    body: JSON.stringify({ class_no: classNo, completed }),
  }),
  resetCycle: (cycleId) => apiRequest(`/cycles/${cycleId}/reset/`, { method: 'POST' }),

  // Analytics
  getWalletAnalytics: () => apiRequest('/analytics/wallet/'),

  // Exams
  getExams: (studentId, batchId) => {
    const params = new URLSearchParams();
    if (studentId) params.append('student_id', studentId);
    if (batchId) params.append('batch_id', batchId);
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
};
