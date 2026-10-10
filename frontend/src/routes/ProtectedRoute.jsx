import React from 'react';
import { Navigate } from 'react-router-dom';
import { useAuth } from '../context/auth';
import ForcePasswordChange from '../pages/ForcePasswordChange';
import { Spinner } from '../components/common/States';

export function ProtectedRoute({ children, requiredRole }) {
  const { user, token, loading } = useAuth();

  if (loading) {
    return (
      <div className="min-h-screen bg-slate-950 flex items-center justify-center">
        <Spinner className="w-10 h-10 border-4" />
      </div>
    );
  }

  if (!token || !user) {
    return <Navigate to="/login" replace />;
  }

  // A password someone else chose must be replaced before using the app.
  if (user.must_change_password) {
    return <ForcePasswordChange />;
  }

  if (requiredRole && user.role !== requiredRole) {
    return <Navigate to={user.role === 'TUTOR' ? '/tutor' : '/student'} replace />;
  }

  return children;
}
