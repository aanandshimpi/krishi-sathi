export function createOtpService({
  twoFactorApiKey = process.env.TWOFACTOR_API_KEY,
  fast2smsApiKey = process.env.FAST2SMS_API_KEY,
  authKey = process.env.MSG91_AUTH_KEY,
  templateId = process.env.MSG91_TEMPLATE_ID,
  devMode = process.env.OTP_DEV_MODE === 'true',
  fetchImpl = fetch,
} = {}) {
  // In-memory OTP storage for providers where OTP is generated on our server (Fast2SMS or dev mode)
  const localOtps = new Map();

  const provider = twoFactorApiKey
    ? '2factor'
    : fast2smsApiKey
    ? 'fast2sms'
    : authKey && templateId
    ? 'msg91'
    : devMode
    ? 'dev'
    : 'unconfigured';
  console.log('🔧 OTP provider selected:', provider);

  const configured = provider !== 'unconfigured';

  return {
    configured,
    provider,

    async send(phone) {
      if (!configured) {
        throw Object.assign(
          new Error('SMS OTP service is not configured. Please add an API key.'),
          { status: 503 }
        );
      }

      // Generate a secure 6-digit OTP code for local providers
      const code = String(Math.floor(100000 + Math.random() * 900000));
      localOtps.set(phone, {
        code,
        expires: Date.now() + 5 * 60 * 1000, // 5 minutes
      });

      // 1. 2Factor.in (AUTOGEN OTP)
      if (provider === '2factor') {
        const url = `https://2factor.in/API/V1/${encodeURIComponent(twoFactorApiKey)}/SMS/${phone}/AUTOGEN`;
        console.log('🔗 2Factor request URL →', url);
        try {
          const res = await fetchImpl(url, { signal: AbortSignal.timeout(10000) });
          console.log('🔢 2Factor HTTP status →', res.status);
          const data = await res.json();
            console.log('2Factor response:', data);
          if (data?.Status !== 'Success') {
            console.error('2Factor send error:', data);
            throw new Error(data?.Details || 'Failed to send OTP via 2Factor');
          }
          // Store sessionId from 2Factor for verification
          localOtps.set(phone, { sessionId: data.Details, expires: Date.now() + 5 * 60 * 1000 });
          return;
        } catch (e) {
          console.error('2Factor network error:', e.message);
          throw Object.assign(new Error('SMS delivery failed. Check your network or SMS credits.'), { status: 503 });
        }
      }

      // 2. Fast2SMS Quick OTP
      if (provider === 'fast2sms') {
        const url = new URL('https://www.fast2sms.com/dev/bulkV2');
        url.searchParams.set('authorization', fast2smsApiKey);
        url.searchParams.set('route', 'otp');
        url.searchParams.set('variables_values', code);
        url.searchParams.set('numbers', phone);
        try {
          const res = await fetchImpl(url, {
            headers: { accept: 'application/json' },
            signal: AbortSignal.timeout(10000),
          });
          const data = await res.json();
          if (!data?.return) {
            console.error('Fast2SMS send error:', data);
            const msg = Array.isArray(data?.message) ? data.message.join(', ') : (data?.message || 'Failed to send OTP via Fast2SMS');
            throw Object.assign(new Error(`SMS delivery failed: ${msg}`), { status: 503 });
          }
          return;
        } catch (e) {
          console.error('Fast2SMS network error:', e.message);
          if (e.status) throw e;
          throw Object.assign(new Error(`SMS delivery failed: ${e.message}`), { status: 503 });
        }
      }

      // 3. MSG91
      if (provider === 'msg91') {
        const url = new URL('https://control.msg91.com/api/v5/otp');
        url.searchParams.set('template_id', templateId);
        url.searchParams.set('mobile', `91${phone}`);
        url.searchParams.set('otp_length', '6');
        url.searchParams.set('otp_expiry', '5');
        const res = await fetchImpl(url, {
          method: 'POST',
          headers: { authkey: authKey, 'Content-Type': 'application/json', Accept: 'application/json' },
          body: '{}',
          signal: AbortSignal.timeout(10000),
        });
        const data = await res.json();
        if (!res.ok || data?.type !== 'success') {
          throw Object.assign(new Error('OTP service could not complete the request.'), { status: 503 });
        }
        return;
      }

      // 4. Development mode fallback (logs OTP clearly in terminal console)
      if (provider === 'dev') {
        console.log(`\n========================================`);
        console.log(`[DEV OTP] Mobile: ${phone} | Verification Code: ${code}`);
        console.log(`========================================\n`);
      }
    },

    async verify(phone, code) {
      if (!configured) {
        throw Object.assign(new Error('SMS login is not configured yet.'), { status: 503 });
      }

      // 1. 2Factor.in verification
      if (provider === '2factor') {
        const session = localOtps.get(phone);
        const sessionId = session?.sessionId;
        const verifyEndpoint = sessionId ? 'VERIFY' : 'VERIFY3';
        const verifyTarget = sessionId || phone;
        const url = `https://2factor.in/API/V1/${encodeURIComponent(twoFactorApiKey)}/SMS/${verifyEndpoint}/${encodeURIComponent(verifyTarget)}/${encodeURIComponent(code)}`;
        try {
          const res = await fetchImpl(url, { signal: AbortSignal.timeout(10000) });
          const data = await res.json();
          console.log('🔢 2Factor verify response:', data);
          const matched = data?.Status === 'Success' && /OTP Matched/i.test(String(data?.Details || ''));
          if (matched) {
            localOtps.delete(phone);
            return true;
          }
          return false;
        } catch (e) {
          console.error('2Factor verify error:', e.message);
          return false;
        }
      }

      // 2. MSG91 verification
      if (provider === 'msg91') {
        const url = new URL('https://control.msg91.com/api/v5/otp/verify');
        url.searchParams.set('mobile', `91${phone}`);
        url.searchParams.set('otp', code);
        const res = await fetchImpl(url, {
          headers: { authkey: authKey, Accept: 'application/json' },
          signal: AbortSignal.timeout(10000),
        });
        const data = await res.json();
        return data?.type === 'success' && /verified success|number_verified_successfully/i.test(String(data.message));
      }

      // 3. Fast2SMS & Dev Mode local verification
      const entry = localOtps.get(phone);
      if (!entry) return false;
      if (Date.now() > entry.expires) {
        localOtps.delete(phone);
        return false;
      }
      if (entry.code === code) {
        localOtps.delete(phone);
        return true;
      }
      return false;
    },
  };
}
