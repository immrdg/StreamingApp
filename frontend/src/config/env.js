const getEnv = (key, fallback) => {
  // First try window object (runtime config from ConfigMap)
  if (window[key] !== undefined && window[key] !== '') {
    return window[key];
  }
  // Then try build-time environment variables
  const value = process.env[key];
  return value === undefined || value === '' ? fallback : value;
};

export const AUTH_API_URL = getEnv('REACT_APP_AUTH_API_URL', '/api/auth');
export const STREAMING_API_URL = getEnv('REACT_APP_STREAMING_API_URL', '/api/streaming');
export const STREAMING_PUBLIC_URL = getEnv('REACT_APP_STREAMING_PUBLIC_URL', '');
export const ADMIN_API_URL = getEnv('REACT_APP_ADMIN_API_URL', '/api/admin');
export const CHAT_API_URL = getEnv('REACT_APP_CHAT_API_URL', '/api/chat');
export const CHAT_SOCKET_URL = getEnv('REACT_APP_CHAT_SOCKET_URL', '');
