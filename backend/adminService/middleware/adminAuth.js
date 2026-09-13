const jwt = require('jsonwebtoken');

const adminAuth = (req, res, next) => {
  try {
    // Development mode: skip auth if ADMIN_AUTH_BYPASS is set
    if (process.env.ADMIN_AUTH_BYPASS === 'true') {
      req.user = {
        _id: 'local-dev-user',
        email: 'admin@localhost',
        role: 'admin',
      };
      return next();
    }

    const authHeader = req.headers.authorization || '';
    const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;

    if (!token) {
      return res.status(401).json({
        success: false,
        message: 'Authorization token missing',
      });
    }

    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    if (!decoded || decoded.role !== 'admin') {
      return res.status(403).json({
        success: false,
        message: 'Admin privileges required',
      });
    }

    req.user = {
      _id: decoded.sub,
      email: decoded.email,
      role: decoded.role,
    };

    next();
  } catch (error) {
    console.error('Admin auth error:', error);
    res.status(401).json({
      success: false,
      message: 'Invalid or expired token',
    });
  }
};

module.exports = { adminAuth };
