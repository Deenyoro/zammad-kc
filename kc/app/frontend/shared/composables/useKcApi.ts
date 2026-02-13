// KC: REST API helpers for calling backend endpoints from the Vue 3
// desktop-view.
//
// The desktop-view is GraphQL-first, but KC features use existing REST
// controllers. These helpers provide thin wrappers around fetch() that
// handle CSRF tokens and JSON serialization.
//
// kcApiFetch  — calls /api/v1/kc/... (KC-namespaced endpoints)
// zammadApiFetch — calls /api/v1/... (standard Zammad endpoints)

import { getCSRFToken } from '#shared/server/apollo/utils/csrfToken.ts'

export interface KcApiError {
  error: string
}

const apiFetchInternal = async <T = unknown>(
  url: string,
  options: RequestInit = {},
): Promise<T> => {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    ...(options.headers as Record<string, string>),
  }

  const csrfToken = getCSRFToken()
  if (csrfToken) {
    headers['X-CSRF-Token'] = csrfToken
  }

  const response = await fetch(url, {
    credentials: 'same-origin',
    ...options,
    headers,
  })

  if (!response.ok) {
    let message = `Request failed (${response.status})`
    try {
      const body = (await response.json()) as KcApiError
      if (body.error) message = body.error
    } catch {
      // response body not JSON — use default message
    }
    throw new Error(message)
  }

  // 204 No Content — return empty object instead of crashing on .json()
  if (response.status === 204) {
    return {} as T
  }

  return response.json() as Promise<T>
}

/** Fetch from /api/v1/kc/... (KC-namespaced REST endpoints). */
export const kcApiFetch = async <T = unknown>(
  path: string,
  options: RequestInit = {},
): Promise<T> => {
  return apiFetchInternal<T>(`/api/v1/kc${path}`, options)
}

/** Fetch from /api/v1/... (standard Zammad REST endpoints). */
export const zammadApiFetch = async <T = unknown>(
  path: string,
  options: RequestInit = {},
): Promise<T> => {
  return apiFetchInternal<T>(`/api/v1${path}`, options)
}
