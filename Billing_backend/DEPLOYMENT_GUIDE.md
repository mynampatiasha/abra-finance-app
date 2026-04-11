# Abra Finance Backend — Deployment Guide

## Server Requirements
- Node.js 18+ (LTS recommended)
- MongoDB Atlas connection (already configured)
- Domain: `finance.abragroup.in`
- Port: 3002
- Reverse proxy: nginx or Apache

---

## Step 1 — Install Dependencies on Server

```bash
cd /path/to/Abra_finance_system/Billing_backend
npm install --production
```

---

## Step 2 — Configure Environment Variables

The `.env` file is already configured for production:
- `PORT=3002`
- `NODE_ENV=production`
- `MONGODB_URI` points to Atlas cluster
- `FINANCE_API_BASE_URL=https://finance.abragroup.in`

Verify the `.env` file exists and has correct values.

---

## Step 3 — Setup PM2 (Process Manager)

Install PM2 globally:
```bash
npm install -g pm2
```

Start the backend:
```bash
pm2 start index.js --name abra-finance-backend
pm2 save
pm2 startup
```

Check status:
```bash
pm2 status
pm2 logs abra-finance-backend
```

---

## Step 4 — Configure Nginx Reverse Proxy

Create nginx config at `/etc/nginx/sites-available/finance.abragroup.in`:

```nginx
server {
    listen 80;
    server_name finance.abragroup.in;

    # Redirect HTTP to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name finance.abragroup.in;

    # SSL certificates (use Let's Encrypt certbot)
    ssl_certificate /etc/letsencrypt/live/finance.abragroup.in/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/finance.abragroup.in/privkey.pem;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Proxy to Node.js backend on port 3002
    location / {
        proxy_pass http://localhost:3002;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        
        # Increase timeouts for large file uploads
        proxy_connect_timeout 600;
        proxy_send_timeout 600;
        proxy_read_timeout 600;
        send_timeout 600;
    }

    # Static file serving for uploads
    location /uploads {
        alias /path/to/Abra_finance_system/Billing_backend/uploads;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    # Health check endpoint
    location /health {
        proxy_pass http://localhost:3002/health;
        access_log off;
    }
}
```

Enable the site:
```bash
sudo ln -s /etc/nginx/sites-available/finance.abragroup.in /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

---

## Step 5 — Setup SSL with Let's Encrypt

```bash
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d finance.abragroup.in
```

Auto-renewal is configured automatically by certbot.

---

## Step 6 — Test the Deployment

1. Check backend health:
   ```bash
   curl https://finance.abragroup.in/health
   ```

2. Expected response:
   ```json
   {
     "status": "ok",
     "service": "abra-finance-module",
     "timestamp": "2026-04-01T...",
     "db": "connected"
   }
   ```

3. Test from Flutter app:
   - Open the app
   - Login should work
   - Dashboard should load

---

## Troubleshooting

### Backend not starting
```bash
pm2 logs abra-finance-backend --lines 100
```

### MongoDB connection issues
Check the `MONGODB_URI` in `.env` — ensure the IP whitelist in MongoDB Atlas includes your server IP.

### CORS errors
The backend already allows `https://finance.abragroup.in` in CORS config. If issues persist, check the `ALLOWED_ORIGINS` in `.env`.

### 502 Bad Gateway
- Check if backend is running: `pm2 status`
- Check nginx error logs: `sudo tail -f /var/log/nginx/error.log`
- Verify port 3002 is not blocked by firewall

---

## Monitoring

View logs:
```bash
pm2 logs abra-finance-backend
```

Restart backend:
```bash
pm2 restart abra-finance-backend
```

Stop backend:
```bash
pm2 stop abra-finance-backend
```

---

## Security Checklist

- ✅ HTTPS enabled with valid SSL certificate
- ✅ MongoDB connection uses authentication
- ✅ JWT secrets are strong and unique
- ✅ CORS restricted to known origins
- ✅ File upload size limits configured
- ✅ Rate limiting enabled (100 requests/minute)
- ✅ Environment variables not committed to git

---

## Backup Strategy

1. MongoDB backups are handled by MongoDB Atlas (automatic)
2. Uploaded files in `/uploads` folder should be backed up regularly:
   ```bash
   rsync -avz /path/to/Billing_backend/uploads /backup/location/
   ```

---

## Updates & Maintenance

To deploy updates:
```bash
cd /path/to/Abra_finance_system/Billing_backend
git pull origin main
npm install --production
pm2 restart abra-finance-backend
```

---

## Support

For issues, check:
1. PM2 logs: `pm2 logs abra-finance-backend`
2. Nginx logs: `/var/log/nginx/error.log`
3. MongoDB Atlas monitoring dashboard
