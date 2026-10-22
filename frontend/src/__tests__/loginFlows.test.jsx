import React from 'react';
import { act } from 'react';
import { createRoot } from 'react-dom/client';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('../api/client', () => ({
  api: {
    getMeta: vi.fn(),
    getTutors: vi.fn(async () => []),
    requestPasswordReset: vi.fn(),
    verifyResetCode: vi.fn(),
    confirmPasswordReset: vi.fn(),
  },
}));

// Fresh modules per test: the Google client ID is looked up once per page load.
let api;
let AuthContext;
let LoginPage;
async function loadModules() {
  vi.resetModules();
  ({ api } = await import('../api/client'));
  ({ AuthContext } = await import('../context/auth'));
  ({ default: LoginPage } = await import('../pages/LoginPage'));
}

globalThis.IS_REACT_ACT_ENVIRONMENT = true;

let container;
let root;
const auth = { login: vi.fn(), loginWithGoogle: vi.fn(), registerTutor: vi.fn(), registerStudent: vi.fn() };

function render() {
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  act(() => {
    root.render(
      <AuthContext.Provider value={auth}>
        <MemoryRouter initialEntries={['/login']}>
          <Routes>
            <Route path="/login" element={<LoginPage />} />
            <Route path="/tutor" element={<p>tutor home</p>} />
            <Route path="/student" element={<p>student home</p>} />
          </Routes>
        </MemoryRouter>
      </AuthContext.Provider>,
    );
  });
}

const flush = () => act(async () => {
  for (let i = 0; i < 5; i += 1) await Promise.resolve();
});

const byText = (text) => [...container.querySelectorAll('button')].find((b) => b.textContent.includes(text));

async function type(selector, value) {
  const input = container.querySelector(selector);
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
  await act(async () => {
    setter.call(input, value);
    input.dispatchEvent(new Event('input', { bubbles: true }));
  });
}

async function click(button) {
  await act(async () => button.click());
  await flush();
}

async function submit(selector = 'form') {
  await act(async () => container.querySelector(selector).requestSubmit());
  await flush();
}

beforeEach(async () => {
  vi.clearAllMocks();
  delete window.google;
  await loadModules();
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('forgot password', () => {
  it('goes email → code → new password → back to sign in with the username filled in', async () => {
    api.getMeta.mockResolvedValue({ auth: { google_client_id: '', password_reset_email: true } });
    api.requestPasswordReset.mockResolvedValue({ message: 'Check your inbox.' });
    api.verifyResetCode.mockResolvedValue({ uid: 'U', token: 'T', username: 'rina' });
    api.confirmPasswordReset.mockResolvedValue({ message: 'ok' });
    render();
    await flush();

    await click(byText('Forgot your password?'));
    await type('#reset-identifier', 'rina@gmail.com');
    await submit();
    expect(api.requestPasswordReset).toHaveBeenCalledWith('rina@gmail.com');
    expect(container.textContent).toContain('Check your inbox.');
    expect(byText('Send again in')).toBeTruthy(); // resend waits for the cooldown

    await type('#reset-code', '12a 3456');
    expect(container.querySelector('#reset-code').value).toBe('123456');
    await submit();
    expect(api.verifyResetCode).toHaveBeenCalledWith('rina@gmail.com', '123456');
    expect(container.textContent).toContain('For the account “rina”');

    await type('#reset-new', 'BrandNew456!y');
    await type('#reset-confirm', 'BrandNew456!y');
    await submit();
    expect(api.confirmPasswordReset).toHaveBeenCalledWith('U', 'T', 'BrandNew456!y');
    expect(container.textContent).toContain('Password changed');

    await click(byText('Go to sign in'));
    expect(container.querySelector('#username').value).toBe('rina');
  });

  it('shows a wrong code and warns when the server cannot send email', async () => {
    api.getMeta.mockResolvedValue({ auth: { google_client_id: '', password_reset_email: false } });
    api.requestPasswordReset.mockResolvedValue({ message: 'sent' });
    api.verifyResetCode.mockRejectedValue(new Error('That code is not correct or has expired.'));
    render();
    await flush();
    await click(byText('Forgot your password?'));
    await flush();
    expect(container.textContent).toContain('Email sending is not set up');
    await type('#reset-identifier', 'rina');
    await submit();
    await type('#reset-code', '000000');
    await submit();
    expect(container.querySelector('[role="alert"]').textContent).toContain('not correct');
  });
});

describe('sign in with Google', () => {
  function fakeGoogle() {
    const gsi = { initialize: vi.fn(), renderButton: vi.fn() };
    window.google = { accounts: { id: gsi } };
    return gsi;
  }

  it('signs straight in when the account exists', async () => {
    const gsi = fakeGoogle();
    api.getMeta.mockResolvedValue({ auth: { google_client_id: 'cid.apps.googleusercontent.com' } });
    auth.loginWithGoogle.mockResolvedValue({ role: 'TUTOR' });
    render();
    await flush();
    await flush();
    expect(gsi.renderButton).toHaveBeenCalled();
    expect(gsi.initialize.mock.calls[0][0].client_id).toBe('cid.apps.googleusercontent.com');

    const callback = gsi.initialize.mock.calls[0][0].callback;
    await act(async () => callback({ credential: 'google-token' }));
    await flush();
    expect(auth.loginWithGoogle).toHaveBeenCalledWith('google-token', undefined);
    expect(container.textContent).toContain('tutor home');
  });

  it('asks tutor or student for a new Google account, then creates it', async () => {
    fakeGoogle();
    api.getMeta.mockResolvedValue({ auth: { google_client_id: 'cid.apps.googleusercontent.com' } });
    const notFound = Object.assign(new Error('No account'), {
      code: 'google_account_not_found',
      data: { email: 'rina@gmail.com', name: 'Rina', signup_allowed: true },
    });
    auth.loginWithGoogle.mockRejectedValueOnce(notFound).mockResolvedValueOnce({ role: 'STUDENT' });
    render();
    await flush();
    await flush();
    const { callback } = window.google.accounts.id.initialize.mock.calls[0][0];
    await act(async () => callback({ credential: 'google-token' }));
    await flush();
    expect(container.textContent).toContain('No TuitionTrack account uses rina@gmail.com yet');

    await click(byText("I'm a student"));
    expect(auth.loginWithGoogle).toHaveBeenLastCalledWith('google-token', 'STUDENT');
    expect(container.textContent).toContain('student home');
  });
});
