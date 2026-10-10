import { createContext, useContext } from 'react';

/** The signed-in user and the sign-in/out actions. Provided by <AuthProvider> (AuthContext.jsx). */
export const AuthContext = createContext(null);

export function useAuth() {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}
