import React, { useCallback, useEffect, useState } from 'react';
import { api } from '../api/client';
import { AuthContext } from './auth';

function clearStoredSession() {
  localStorage.removeItem('access_token');
  localStorage.removeItem('refresh_token');
  localStorage.removeItem('user_data');
}

export function AuthProvider({ children }) {
  const [user, setUser] = useState(() => {
    try {
      const saved = localStorage.getItem('user_data');
      return saved ? JSON.parse(saved) : null;
    } catch {
      return null;
    }
  });
  const [token, setToken] = useState(() => localStorage.getItem('access_token'));
  // Only a stored session needs checking; with none there is nothing to wait for.
  const [loading, setLoading] = useState(() => Boolean(localStorage.getItem('access_token')));

  const logout = useCallback(() => {
    api.logout(); // tell the server too, so the session cannot be reused (reads the token before it is cleared)
    clearStoredSession();
    setToken(null);
    setUser(null);
  }, []);

  useEffect(() => {
    if (!token) return undefined;
    let cancelled = false;
    api.getMe()
      .then((profile) => {
        if (cancelled) return;
        setUser(profile);
        localStorage.setItem('user_data', JSON.stringify(profile));
      })
      .catch((err) => {
        if (cancelled) return;
        // Only a refused session signs the user out. Offline or a server hiccup
        // keeps the saved profile so the app opens and each screen reports the problem.
        if (err?.status === 401 || err?.status === 403) logout();
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [token, logout]);

  const login = async (username, password) => {
    const data = await api.login({ username, password });
    localStorage.setItem('access_token', data.access);
    localStorage.setItem('refresh_token', data.refresh);
    localStorage.setItem('user_data', JSON.stringify(data.user));
    setToken(data.access);
    setUser(data.user);
    return data.user;
  };

  const registerTutor = async (formData) => {
    await api.registerTutor(formData);
    return login(formData.username, formData.password);
  };

  const registerStudent = async (formData) => {
    await api.registerStudent(formData);
    return login(formData.username, formData.password);
  };

  // Re-read the signed-in user after they change their details or password.
  const refreshUser = async () => {
    const profile = await api.getMe();
    setUser(profile);
    localStorage.setItem('user_data', JSON.stringify(profile));
    return profile;
  };

  const value = {
    user,
    token,
    loading,
    refreshUser,
    isTutor: user?.role === 'TUTOR',
    isStudent: user?.role === 'STUDENT',
    login,
    registerTutor,
    registerStudent,
    logout,
  };

  return (
    <AuthContext.Provider value={value}>
      {children}
    </AuthContext.Provider>
  );
}
