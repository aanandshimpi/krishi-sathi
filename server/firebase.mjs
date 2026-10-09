import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

let appInstance = null;

export function getFirebaseAdmin() {
  if (appInstance) return appInstance;
  const keyPath = process.env.FIREBASE_SERVICE_ACCOUNT_KEY || resolve('server/firebase-service-account.json');
  if (existsSync(keyPath)) {
    try {
      const serviceAccount = JSON.parse(readFileSync(keyPath, 'utf8'));
      appInstance = initializeApp({
        credential: cert(serviceAccount),
      });
      return appInstance;
    } catch (e) {
      console.error('Failed to initialize Firebase Admin with service account:', e.message);
    }
  }
  return appInstance;
}

export async function verifyFirebaseIdToken(idToken) {
  // Allow test mock token in test / development mode if configured
  if (process.env.NODE_ENV !== 'production' && idToken.startsWith('mock:')) {
    const phone = idToken.slice(5);
    return { phone, uid: `mock-${phone}` };
  }

  getFirebaseAdmin();
  if (!getApps().length) {
    throw Object.assign(
      new Error('Firebase Admin is not configured yet. Please add server/firebase-service-account.json.'),
      { status: 503 }
    );
  }

  const auth = getAuth();
  const decoded = await auth.verifyIdToken(idToken);
  let phone = decoded.phone_number || '';
  if (phone.startsWith('+91')) {
    phone = phone.slice(3);
  } else if (phone.startsWith('+')) {
    phone = phone.slice(1);
  }
  return { phone, uid: decoded.uid, decoded };
}
