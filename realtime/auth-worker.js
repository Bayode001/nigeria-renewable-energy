// Simplified version for Cloudflare Dashboard
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    
    // Check for basic auth
    const authHeader = request.headers.get('Authorization');
    
    if (!authHeader || !authHeader.startsWith('Basic ')) {
      return new Response('Authentication Required', {
        status: 401,
        headers: {
          'WWW-Authenticate': 'Basic realm="Nigeria Energy Dashboard"',
          'Cache-Control': 'no-store, no-cache'
        }
      });
    }
    
    // Extract credentials
    const base64Credentials = authHeader.split(' ')[1];
    const credentials = atob(base64Credentials);
    const [username, password] = credentials.split(':');
    
    // Check against environment variables
    const validUsername = env.DASHBOARD_USERNAME || 'admin';
    const validPassword = env.DASHBOARD_PASSWORD || 'password123';
    
    if (username !== validUsername || password !== validPassword) {
      return new Response('Invalid credentials', { status: 401 });
    }
    
    // Forward to GitHub Pages
    const githubUrl = `https://bayode001.github.io/nigeria-renewable-energy/realtime/`;
    return fetch(githubUrl, request);
  }
};