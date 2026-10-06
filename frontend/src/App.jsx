import React from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { AuthProvider, useAuth } from './context/AuthContext';
import { ProtectedRoute } from './routes/ProtectedRoute';
import LoginPage from './pages/LoginPage';
import TutorDashboard from './pages/TutorDashboard';
import StudentPortal from './pages/StudentPortal';

import TuitionWorkspace from './pages/TuitionWorkspace';
import Toaster from './components/common/Toaster';
import ResetPasswordPage from './pages/ResetPasswordPage';

function RootRedirect() {
  const { user, token, loading } = useAuth();

  if (loading) {
    return (
      <div className="min-h-screen bg-slate-950 flex items-center justify-center">
        <div className="w-10 h-10 rounded-full border-4 border-indigo-500/20 border-t-indigo-500 animate-spin" />
      </div>
    );
  }

  if (!token || !user) {
    return <Navigate to="/login" replace />;
  }

  return <Navigate to={user.role === 'TUTOR' ? '/tutor' : '/student'} replace />;
}

export default function App() {
  return (
    <AuthProvider>
      <BrowserRouter>
        <Routes>
          <Route path="/" element={<RootRedirect />} />
          <Route path="/login" element={<LoginPage />} />
          <Route path="/reset-password" element={<ResetPasswordPage />} />
          <Route
            path="/tutor"
            element={
              <ProtectedRoute requiredRole="TUTOR">
                <TutorDashboard />
              </ProtectedRoute>
            }
          />
          <Route
            path="/tuitions/:id"
            element={
              <ProtectedRoute requiredRole="TUTOR">
                <TuitionWorkspace />
              </ProtectedRoute>
            }
          />
          <Route
            path="/student"
            element={
              <ProtectedRoute requiredRole="STUDENT">
                <StudentPortal />
              </ProtectedRoute>
            }
          />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </BrowserRouter>
      <Toaster />
    </AuthProvider>
  );
}
