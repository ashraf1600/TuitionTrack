import React, { createContext, useContext, useState, useEffect } from 'react';
import { api } from '../api/client';

const AuthContext = createContext(null);

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
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function verifyUser() {
      if (token) {
        try {
          const profile = await api.getMe();
          setUser(profile);
          localStorage.setItem('user_data', JSON.stringify(profile));
        } catch {
          // Token invalid or expired
          logout();
        }
      }
      setLoading(false);
    }
    verifyUser();
  }, [token]);

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

  const logout = () => {
    localStorage.removeItem('access_token');
    localStorage.removeItem('refresh_token');
    localStorage.removeItem('user_data');
    setToken(null);
    setUser(null);
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

export function useAuth() {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}
