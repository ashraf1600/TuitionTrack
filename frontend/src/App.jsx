import React, { Suspense, lazy } from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { AuthProvider } from './context/AuthContext';
import { useAuth } from './context/auth';
import { ProtectedRoute } from './routes/ProtectedRoute';
import LoginPage from './pages/LoginPage';
import Toaster from './components/common/Toaster';
import ResetPasswordPage from './pages/ResetPasswordPage';
import { Spinner } from './components/common/States';

// Each role's pages load on demand: a student never downloads the tutor's exam editor.
const TutorDashboard = lazy(() => import('./pages/TutorDashboard'));
const StudentPortal = lazy(() => import('./pages/StudentPortal'));
const TuitionWorkspace = lazy(() => import('./pages/TuitionWorkspace'));

function FullPageSpinner() {
  return (
    <div className="min-h-screen bg-slate-950 flex items-center justify-center">
      <Spinner className="w-10 h-10 border-4" />
    </div>
  );
}

function RootRedirect() {
  const { user, token, loading } = useAuth();

  if (loading) {
    return <FullPageSpinner />;
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
        <Suspense fallback={<FullPageSpinner />}>
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
        </Suspense>
      </BrowserRouter>
      <Toaster />
    </AuthProvider>
  );
}
