import React, { useEffect, useRef, useState } from 'react';
import { loadGoogleClientId } from '../../utils/googleClientId';

/**
 * "Continue with Google", drawn by Google Identity Services.
 *
 * The OAuth client ID comes from the server (/api/v1/meta/ → auth.google_client_id),
 * with VITE_GOOGLE_CLIENT_ID as a fallback, so it is configured in one place. When
 * neither is set the button renders nothing. Google hands back an ID token
 * ("credential") which the caller sends to POST /auth/google/.
 *
 * In Google Cloud Console the client's "Authorized JavaScript origins" must list
 * this site's address (e.g. https://tuitiontrack-web.onrender.com and
 * http://localhost:5173 plus http://localhost for development).
 */

const GSI_SRC = 'https://accounts.google.com/gsi/client';

let scriptPromise = null;
function loadGoogleScript() {
  if (window.google?.accounts?.id) return Promise.resolve();
  if (!scriptPromise) {
    scriptPromise = new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = GSI_SRC;
      script.async = true;
      script.defer = true;
      script.onload = () => resolve();
      script.onerror = () => {
        scriptPromise = null; // allow a retry on the next render
        reject(new Error('Could not load Google sign-in.'));
      };
      document.head.appendChild(script);
    });
  }
  return scriptPromise;
}

// Google allows one initialize() per page; every button shares it and the latest handler wins.
let initializedFor = '';
let currentHandler = null;

export default function GoogleSignInButton({ onCredential, text = 'continue_with', disabled = false }) {
  const holder = useRef(null);
  const [clientId, setClientId] = useState('');
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    currentHandler = onCredential;
  }, [onCredential]);

  useEffect(() => {
    let cancelled = false;
    loadGoogleClientId().then((id) => {
      if (!cancelled) setClientId(id);
    });
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    if (!clientId) return undefined;
    let cancelled = false;
    loadGoogleScript()
      .then(() => {
        if (cancelled || !holder.current) return;
        const gsi = window.google.accounts.id;
        if (initializedFor !== clientId) {
          gsi.initialize({
            client_id: clientId,
            callback: (response) => {
              if (response?.credential && currentHandler) currentHandler(response.credential);
            },
            ux_mode: 'popup',
            auto_select: false,
            cancel_on_tap_outside: true,
            context: 'signin',
            itp_support: true,
          });
          initializedFor = clientId;
        }
        // Google's button takes a fixed pixel width between 200 and 400.
        const width = Math.max(200, Math.min(400, Math.floor(holder.current.offsetWidth || 320)));
        holder.current.innerHTML = '';
        gsi.renderButton(holder.current, {
          type: 'standard',
          theme: 'filled_black',
          size: 'large',
          text,
          shape: 'pill',
          logo_alignment: 'left',
          width,
        });
      })
      .catch(() => {
        if (!cancelled) setFailed(true);
      });
    return () => {
      cancelled = true;
    };
  }, [clientId, text]);

  if (!clientId) return null;
  if (failed) {
    return <p className="text-center text-xs text-slate-500">Google sign-in could not load. Check your connection or ad blocker.</p>;
  }
  return (
    <div
      className={`flex justify-center min-h-[44px] ${disabled ? 'pointer-events-none opacity-60' : ''}`}
      aria-busy={disabled}
    >
      <div ref={holder} className="w-full max-w-[400px] flex justify-center" />
    </div>
  );
}
