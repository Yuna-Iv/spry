import { z } from 'zod'

import type { ActionItem, AgendaItem } from '@/lib/api'

// The form keeps every value as a string (what inputs hold); toPayload turns them into the API's
// types, with '' meaning "not given" (null).
export const agendaSchema = z.object({
  items: z.array(
    z.object({
      topic: z.string().trim().min(1, 'Topic is required').max(300),
      owner: z.string().max(255),
      minutes: z
        .string()
        .regex(/^\d*$/, 'Whole minutes')
        .refine((v) => v === '' || (Number(v) >= 1 && Number(v) <= 480), '1–480 minutes'),
    }),
  ),
  actionItems: z.array(
    z.object({
      task: z.string().trim().min(1, 'Task is required').max(300),
      owner: z.string().max(255),
      due: z.string(),
    }),
  ),
})

export type AgendaFormValues = z.input<typeof agendaSchema>

export const emptyAgendaValues: AgendaFormValues = { items: [], actionItems: [] }

export const emptyItem = { topic: '', owner: '', minutes: '' }
export const emptyActionItem = { task: '', owner: '', due: '' }

/** Form values from an agenda: the saved one, or (later) the one the parser suggested. */
export function toAgendaFormValues(agenda: {
  items: AgendaItem[]
  action_items: ActionItem[]
}): AgendaFormValues {
  return {
    items: agenda.items.map((i) => ({
      topic: i.topic,
      owner: i.owner ?? '',
      minutes: i.minutes == null ? '' : String(i.minutes),
    })),
    actionItems: agenda.action_items.map((a) => ({
      task: a.task,
      owner: a.owner ?? '',
      due: a.due ?? '',
    })),
  }
}

const orNull = (value: string) => (value.trim() === '' ? null : value.trim())

export function toPayload(values: AgendaFormValues): {
  items: AgendaItem[]
  action_items: ActionItem[]
} {
  return {
    items: values.items.map((i) => ({
      topic: i.topic.trim(),
      owner: orNull(i.owner),
      minutes: i.minutes === '' ? null : Number(i.minutes),
    })),
    action_items: values.actionItems.map((a) => ({
      task: a.task.trim(),
      owner: orNull(a.owner),
      due: orNull(a.due),
    })),
  }
}
