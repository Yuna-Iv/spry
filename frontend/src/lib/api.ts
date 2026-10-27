import { signOut } from 'aws-amplify/auth'
import { format } from 'date-fns'

import { getIdToken } from '@/lib/auth'

export type Participant = {
  id: string
  name: string
  email: string
}

export type Meeting = {
  id: string
  title: string
  description: string
  starts_at: string
  ends_at: string
  place: string
  participants: Participant[]
  created_at: string
}

export type MeetingCreate = {
  title: string
  description: string
  starts_at: string
  ends_at: string
  place: string
  participant_ids: string[]
}

export type ParticipantCreate = {
  name: string
  email: string
}

export type AgendaItem = {
  topic: string
  owner: string | null
  minutes: number | null
}

export type ActionItem = {
  task: string
  owner: string | null
  /** YYYY-MM-DD */
  due: string | null
}

export type Agenda = {
  items: AgendaItem[]
  action_items: ActionItem[]
  /** Saved from a parsed (pasted) agenda rather than typed by hand. */
  from_ai: boolean
  updated_at: string | null
}

/** What the agenda parser proposed; stored next to the saved agenda as the quality signal. */
export type AiSuggestion = {
  agenda: unknown
  model: string
  prompt_version: string
  source_text: string
}

/** What the agenda parser returns: a suggestion for the agenda form, never saved by itself. */
export type ParsedAgenda = {
  title: string | null
  /** ISO 8601, with the user's offset if the model gave one. */
  starts_at: string | null
  duration_minutes: number | null
  items: AgendaItem[]
  action_items: ActionItem[]
  language: string
}

export type ParseResult = {
  agenda: ParsedAgenda
  model: string
  prompt_version: string
}

export type AgendaSave = {
  items: AgendaItem[]
  action_items: ActionItem[]
  ai_suggestion?: AiSuggestion | null
}

export class ApiError extends Error {
  readonly status: number

  constructor(status: number, message: string) {
    super(message)
    this.status = status
  }
}

// Backend origin, set at build time for AWS (the Lambda function URL). Empty locally,
// where the Vite dev server or nginx proxies /api to the backend.
const API_URL = (import.meta.env.VITE_API_URL ?? '').replace(/\/+$/, '')
// The agenda parser's function URL (infra/ai.yml), set at build time. Empty locally, where the
// Vite dev server proxies /parse to `make dev-parser`.
const PARSER_URL = (import.meta.env.VITE_PARSER_URL ?? '').replace(/\/+$/, '')
export const MAX_AGENDA_TEXT = 10_000

type ValidationIssue = { loc?: (string | number)[]; msg: string }

function errorMessage(detail: unknown, fallback: string): string {
  if (typeof detail === 'string') return detail
  if (Array.isArray(detail)) {
    return (detail as ValidationIssue[])
      .map((issue) => {
        const field = issue.loc?.filter((part) => part !== 'body').join('.')
        const msg = issue.msg.replace(/^Value error, /, '')
        return field ? `${field}: ${msg}` : msg
      })
      .join('; ')
  }
  return fallback
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const token = await getIdToken()
  const response = await fetch(`${API_URL}/api${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...(token && { Authorization: `Bearer ${token}` }),
      ...init?.headers,
    },
  })

  // The session is gone (revoked, or the refresh token expired): sign out, which sends the
  // user back to the login page (see AuthProvider).
  if (response.status === 401) await signOut().catch(() => undefined)

  if (!response.ok) {
    let detail: unknown
    try {
      detail = (await response.json()).detail
    } catch {
      // body was not JSON
    }
    throw new ApiError(response.status, errorMessage(detail, response.statusText))
  }

  if (response.status === 204) return undefined as T
  return response.json() as Promise<T>
}

export const api = {
  listMeetings: () => request<Meeting[]>('/meetings'),
  createMeeting: (data: MeetingCreate) =>
    request<Meeting>('/meetings', { method: 'POST', body: JSON.stringify(data) }),
  updateMeeting: ({ id, ...data }: MeetingCreate & { id: string }) =>
    request<Meeting>(`/meetings/${id}`, { method: 'PUT', body: JSON.stringify(data) }),
  deleteMeeting: (id: string) => request<void>(`/meetings/${id}`, { method: 'DELETE' }),
  listParticipants: () => request<Participant[]>('/participants'),
  createParticipant: (data: ParticipantCreate) =>
    request<Participant>('/participants', { method: 'POST', body: JSON.stringify(data) }),
  getAgenda: (meetingId: string) => request<Agenda>(`/meetings/${meetingId}/agenda`),
  saveAgenda: ({ meetingId, ...data }: AgendaSave & { meetingId: string }) =>
    request<Agenda>(`/meetings/${meetingId}/agenda`, {
      method: 'PUT',
      body: JSON.stringify(data),
    }),
}

/** Messages for the parser's errors; the user can always type the agenda by hand instead. */
const PARSE_ERRORS: Record<number, string> = {
  401: 'Your session has expired. Sign in again.',
  413: `The text is too long: paste at most ${MAX_AGENDA_TEXT.toLocaleString('en')} characters.`,
  422: 'No agenda found in this text. Check what you pasted, or type the agenda by hand.',
  429: 'The AI service is busy right now. Try again in a minute.',
  502: 'The AI service is not available right now. Try again later, or type the agenda by hand.',
  503: 'The AI service is not available right now. Try again later, or type the agenda by hand.',
}

/**
 * Sends pasted text to the agenda parser. It only suggests: the result pre-fills the agenda
 * form, and Save goes through the main API. `signal` cancels the request (the Cancel button).
 */
export async function parseAgenda(text: string, signal: AbortSignal): Promise<ParseResult> {
  const token = await getIdToken()
  let response: Response
  try {
    response = await fetch(`${PARSER_URL}/parse`, {
      method: 'POST',
      signal,
      headers: {
        'Content-Type': 'application/json',
        ...(token && { Authorization: `Bearer ${token}` }),
      },
      body: JSON.stringify({
        text,
        // The user's "Monday" is in the user's time zone, not the function's (UTC).
        today: format(new Date(), 'yyyy-MM-dd'),
        tz: Intl.DateTimeFormat().resolvedOptions().timeZone,
      }),
    })
  } catch (error) {
    if (error instanceof DOMException && error.name === 'AbortError') throw error
    throw new ApiError(0, 'Network error: check your connection and try again.')
  }
  if (response.status === 401) await signOut().catch(() => undefined)
  if (!response.ok) {
    throw new ApiError(
      response.status,
      PARSE_ERRORS[response.status] ?? `The agenda could not be read (${response.status}).`,
    )
  }
  return response.json() as Promise<ParseResult>
}
