import React, { useState, useEffect } from 'react';
import Login from './components/Login';
import HysteriaAdminPanel from './components/HysteriaAdminPanel';

function App() {
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    // Check for existing session on app load
    const authData = localStorage.getItem('hysteria-admin-auth');
    if (authData) {
      try {
        const parsed = JSON.parse(authData);
        // Check if session is not too old (24 hours)
        const loginTime = new Date(parsed.loggedInAt);
        const now = new Date();
        const hoursDiff = (now - loginTime) / (1000 * 60 * 60);
        
        if (hoursDiff < 24) {
          setIsAuthenticated(true);
        } else {
          // Session expired, clear it
          localStorage.removeItem('hysteria-admin-auth');
        }
      } catch (error) {
        // Invalid session data, clear it
        localStorage.removeItem('hysteria-admin-auth');
      }
    }
    setLoading(false);
  }, []);

  const handleLogin = () => {
    setIsAuthenticated(true);
  };

  const handleLogout = () => {
    localStorage.removeItem('hysteria-admin-auth');
    setIsAuthenticated(false);
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-gray-50 flex items-center justify-center">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600"></div>
      </div>
    );
  }

  if (!isAuthenticated) {
    return <Login onLogin={handleLogin} />;
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <HysteriaAdminPanel onLogout={handleLogout} />
    </div>
  );
}

export default App;
