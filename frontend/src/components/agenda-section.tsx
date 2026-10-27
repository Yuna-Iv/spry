import { useState } from 'react'
import { format, parseISO } from 'date-fns'
import { ListChecksIcon, PencilIcon, PlusIcon } from 'lucide-react'

import { AgendaForm } from '@/components/agenda-form'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import { useAgenda } from '@/hooks/queries'
import { emptyAgendaValues, toAgendaFormValues } from '@/lib/agenda'
import type { Agenda } from '@/lib/api'

/** The agenda block of the meeting details: shows the saved agenda, or the form to edit it. */
export function AgendaSection({ meetingId }: { meetingId: string }) {
  const agenda = useAgenda(meetingId)
  const [editing, setEditing] = useState(false)
  const isEmpty = !agenda.data || agenda.data.items.length + agenda.data.action_items.length === 0

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center justify-between gap-2">
        <h3 className="flex items-center gap-2 text-lg">
          <ListChecksIcon className="size-4" />
          Agenda
        </h3>
        {!editing && agenda.isSuccess && (
          <Button variant="outline" size="sm" onClick={() => setEditing(true)}>
            {isEmpty ? <PlusIcon /> : <PencilIcon />}
            {isEmpty ? 'Add agenda' : 'Edit agenda'}
          </Button>
        )}
      </div>

      {agenda.isPending && <Skeleton className="h-16 w-full" />}
      {agenda.isError && (
        <p className="text-sm text-destructive">
          Could not load the agenda: {agenda.error.message}
        </p>
      )}

      {agenda.isSuccess &&
        (editing ? (
          <AgendaForm
            meetingId={meetingId}
            initialValues={isEmpty ? emptyAgendaValues : toAgendaFormValues(agenda.data)}
            onCancel={() => setEditing(false)}
            onSaved={() => setEditing(false)}
          />
        ) : isEmpty ? (
          <p className="text-muted-foreground">No agenda yet.</p>
        ) : (
          <AgendaView agenda={agenda.data} />
        ))}
    </div>
  )
}

function AgendaView({ agenda }: { agenda: Agenda }) {
  return (
    <div className="flex flex-col gap-4">
      {agenda.items.length > 0 && (
        <ol className="flex list-decimal flex-col gap-1.5 pl-5">
          {agenda.items.map((item, index) => (
            <li key={index}>
              <span>{item.topic}</span>
              <Meta parts={[item.owner, item.minutes && `${item.minutes} min`]} />
            </li>
          ))}
        </ol>
      )}
      {agenda.action_items.length > 0 && (
        <div className="flex flex-col gap-1.5">
          <h4 className="text-sm font-semibold">Action items</h4>
          <ul className="flex list-disc flex-col gap-1.5 pl-5">
            {agenda.action_items.map((item, index) => (
              <li key={index}>
                <span>{item.task}</span>
                <Meta
                  parts={[item.owner, item.due && `by ${format(parseISO(item.due), 'EEE, d MMM')}`]}
                />
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  )
}

function Meta({ parts }: { parts: (string | number | null | undefined | false)[] }) {
  const text = parts.filter(Boolean).join(' · ')
  return text ? <span className="text-sm text-muted-foreground"> — {text}</span> : null
}
