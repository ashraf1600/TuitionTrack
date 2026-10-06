import React from 'react';
import { Navigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import ForcePasswordChange from '../pages/ForcePasswordChange';

export function ProtectedRoute({ children, requiredRole }) {
  const { user, token, loading } = useAuth();

  if (loading) {
    return (
      <div className="min-h-screen bg-slate-900 flex items-center justify-center">
        <div className="w-10 h-10 rounded-full border-4 border-indigo-500/20 border-t-indigo-500 animate-spin" />
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
