import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { apiError, apiRequest } from '../api/client';

const json = (status, body, headers = {}) =>
  new Response(body === undefined ? null : JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json', ...headers },
  });

describe('apiError', () => {
  it('uses the message the API sends and keeps code and field errors', () => {
    const err = apiError(400, { message: 'title: This field is required.', code: 'validation_error', errors: { title: ['This field is required.'] } });
    expect(err.message).toBe('title: This field is required.');
    expect(err.status).toBe(400);
    expect(err.code).toBe('validation_error');
    expect(err.fieldErrors).toEqual({ title: ['This field is required.'] });
  });

  it('prefers error/detail and flattens bare field errors from older endpoints', () => {
    expect(apiError(403, { error: 'Students only.' }).message).toBe('Students only.');
    expect(apiError(400, { student_id: ['Invalid student id.'] }).message).toBe('student_id: Invalid student id.');
  });

  it('never shows an HTML error page and explains gateway failures', () => {
    expect(apiError(500, '<!doctype html><html>Server Error</html>').message).toMatch(/went wrong on the server/);
    expect(apiError(503, null).message).toMatch(/not available right now/);
  });
});

describe('apiRequest', () => {
  beforeEach(() => {
    localStorage.clear();
    vi.stubGlobal('fetch', vi.fn());
  });
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('sends JSON content type only when there is a body, and the bearer token', async () => {
    localStorage.setItem('access_token', 'abc');
    fetch.mockResolvedValueOnce(json(200, { ok: true }));
    await apiRequest('/auth/me/');
    const [, init] = fetch.mock.calls[0];
    expect(init.headers.Authorization).toBe('Bearer abc');
    expect(init.headers['Content-Type']).toBeUndefined();

    fetch.mockResolvedValueOnce(json(201, { id: 1 }));
    await apiRequest('/homework/', { method: 'POST', body: JSON.stringify({ title: 'x' }) });
    expect(fetch.mock.calls[1][1].headers['Content-Type']).toBe('application/json');
  });

  it('turns a network failure into a readable offline message', async () => {
    fetch.mockRejectedValueOnce(new TypeError('Failed to fetch'));
    await expect(apiRequest('/tuitions/')).rejects.toThrow(/Cannot reach the server/);
  });

  it('renews an expired access token once and retries the request', async () => {
    localStorage.setItem('access_token', 'old');
    localStorage.setItem('refresh_token', 'refresh');
    fetch
      .mockResolvedValueOnce(json(401, { detail: 'expired', code: 'token_not_valid' }))
      .mockResolvedValueOnce(json(200, { access: 'new' }))
      .mockResolvedValueOnce(json(200, [{ id: 1 }]));
    const data = await apiRequest('/tuitions/');
    expect(data).toEqual([{ id: 1 }]);
    expect(localStorage.getItem('access_token')).toBe('new');
    expect(fetch.mock.calls[2][1].headers.Authorization).toBe('Bearer new');
  });

  it('collects every page of a paginated list and fails loudly when a page fails', async () => {
    fetch
      .mockResolvedValueOnce(json(200, { count: 3, next: 'http://api/api/v1/students/?page=2', results: [{ id: 1 }, { id: 2 }] }))
      .mockResolvedValueOnce(json(200, { count: 3, next: null, results: [{ id: 3 }] }));
    const data = await apiRequest('/students/');
    expect(data.results.map((s) => s.id)).toEqual([1, 2, 3]);
    expect(fetch.mock.calls[1][0]).toBe('/api/v1/students/?page=2');

    fetch
      .mockResolvedValueOnce(json(200, { count: 3, next: 'http://api/api/v1/students/?page=2', results: [{ id: 1 }] }))
      .mockResolvedValueOnce(json(500, { message: 'boom' }));
    await expect(apiRequest('/students/')).rejects.toThrow('boom');
  });

  it('returns null for 204 No Content', async () => {
    fetch.mockResolvedValueOnce(new Response(null, { status: 204 }));
    await expect(apiRequest('/homework/1/', { method: 'DELETE' })).resolves.toBeNull();
  });
});

describe('session renewal', () => {
  beforeEach(() => {
    localStorage.clear();
    vi.stubGlobal('fetch', vi.fn());
  });
  afterEach(() => vi.unstubAllGlobals());

  it('keeps the session when the refresh call cannot reach the server', async () => {
    localStorage.setItem('access_token', 'old');
    localStorage.setItem('refresh_token', 'refresh');
    fetch
      .mockResolvedValueOnce(json(401, { detail: 'expired' }))
      .mockRejectedValueOnce(new TypeError('Failed to fetch'));
    await expect(apiRequest('/tuitions/')).rejects.toThrow('expired');
    expect(localStorage.getItem('refresh_token')).toBe('refresh');
  });
});
