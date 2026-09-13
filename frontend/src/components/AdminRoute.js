import React from 'react';
import { Navigate, useLocation } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';

export const AdminRoute = ({ children }) => {
  const { user, loading } = useAuth();
  const location = useLocation();

  if (loading) {
    return <div>Loading...</div>;
  }

  // Bypass admin check for development/testing
  if (process.env.REACT_APP_SKIP_AUTH === 'true') {
    return children;
  }

  if (!user || user.role !== 'admin') {
    return <Navigate to="/browse" state={{ from: location }} replace />;
  }

  return children;
};






