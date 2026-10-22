import { useEffect, useState } from 'react';
import { api } from '../api/client';

/** The Google OAuth client ID from the server (/meta/ → auth.google_client_id), or VITE_GOOGLE_CLIENT_ID. */
let clientIdPromise = null;
export function loadGoogleClientId() {
  if (!clientIdPromise) {
    const fallback = (import.meta.env.VITE_GOOGLE_CLIENT_ID || '').trim();
    clientIdPromise = api.getMeta()
      .then((meta) => meta?.auth?.google_client_id || fallback)
      .catch(() => {
        clientIdPromise = null; // the server may be waking up; ask again next time
        return fallback;
      });
  }
  return clientIdPromise;
}


/** True once a Google client ID is known, i.e. the Google button will show. */
export function useGoogleAvailable() {
  const [available, setAvailable] = useState(false);
  useEffect(() => {
    let cancelled = false;
    loadGoogleClientId().then((id) => {
      if (!cancelled) setAvailable(Boolean(id));
    });
    return () => {
      cancelled = true;
    };
  }, []);
  return available;
}
