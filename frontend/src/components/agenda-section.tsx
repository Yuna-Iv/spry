import { useState } from 'react'
import { format, isValid, parseISO } from 'date-fns'
import { ListChecksIcon, PencilIcon, PlusIcon, SparklesIcon } from 'lucide-react'

import { AgendaForm } from '@/components/agenda-form'
import { PasteAgenda } from '@/components/paste-agenda'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import { useAgenda } from '@/hooks/queries'
import { emptyAgendaValues, toAgendaFormValues } from '@/lib/agenda'
import type { Agenda, AiSuggestion, ParsedAgenda, ParseResult } from '@/lib/api'

type Mode =
  | { kind: 'view' }
  | { kind: 'edit' }
  | { kind: 'paste' }
  /** The parser's suggestion in the normal agenda form, until the user saves or cancels. */
  | { kind: 'review'; result: ParseResult; suggestion: AiSuggestion }

/**
 * The agenda block of the meeting details: the saved agenda, the form to type it, or
 * "Paste an agenda". The model only suggests: its result pre-fills the same form, every filled
 * field is marked "suggested", and Save goes through the main API like a typed agenda.
 */
export function AgendaSection({ meetingId }: { meetingId: string }) {
  const agenda = useAgenda(meetingId)
  const [mode, setMode] = useState<Mode>({ kind: 'view' })
  const isEmpty = !agenda.data || agenda.data.items.length + agenda.data.action_items.length === 0
  const back = () => setMode({ kind: 'view' })

  const onParsed = (result: ParseResult, sourceText: string) =>
    setMode({
      kind: 'review',
      result,
      suggestion: {
        agenda: result.agenda,
        model: result.model,
        prompt_version: result.prompt_version,
        source_text: sourceText,
      },
    })

  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h3 className="flex items-center gap-2 text-lg">
          <ListChecksIcon className="size-4" />
          Agenda
        </h3>
        {mode.kind === 'view' && agenda.isSuccess && (
          <div className="flex gap-2">
            <Button variant="outline" size="sm" onClick={() => setMode({ kind: 'paste' })}>
              <SparklesIcon />
              Paste an agenda
            </Button>
            <Button variant="outline" size="sm" onClick={() => setMode({ kind: 'edit' })}>
              {isEmpty ? <PlusIcon /> : <PencilIcon />}
              {isEmpty ? 'Add agenda' : 'Edit agenda'}
            </Button>
          </div>
        )}
      </div>

      {agenda.isPending && <Skeleton className="h-16 w-full" />}
      {agenda.isError && (
        <p className="text-sm text-destructive">
          Could not load the agenda: {agenda.error.message}
        </p>
      )}

      {agenda.isSuccess && mode.kind === 'view' && (
        <>
          {isEmpty ? (
            <p className="text-muted-foreground">No agenda yet.</p>
          ) : (
            <AgendaView agenda={agenda.data} />
          )}
        </>
      )}

      {agenda.isSuccess && mode.kind === 'edit' && (
        <AgendaForm
          meetingId={meetingId}
          initialValues={isEmpty ? emptyAgendaValues : toAgendaFormValues(agenda.data)}
          onCancel={back}
          onSaved={back}
        />
      )}

      {mode.kind === 'paste' && (
        <PasteAgenda
          onParsed={onParsed}
          onCancel={back}
          onTypeByHand={() => setMode({ kind: 'edit' })}
        />
      )}

      {mode.kind === 'review' && (
        <>
          <SuggestionNote parsed={mode.result.agenda} replaces={!isEmpty} />
          <AgendaForm
            // A new suggestion is a new form, with every field marked "suggested" again.
            key={mode.suggestion.source_text}
            meetingId={meetingId}
            initialValues={toAgendaFormValues(mode.result.agenda)}
            suggestion={mode.suggestion}
            onCancel={back}
            onSaved={back}
          />
        </>
      )}
    </div>
  )
}

/** What the model found beyond the agenda itself, for the user to compare with the meeting. */
function SuggestionNote({ parsed, replaces }: { parsed: ParsedAgenda; replaces: boolean }) {
  const start = parsed.starts_at ? parseISO(parsed.starts_at) : null
  const details = [
    parsed.title && `“${parsed.title}”`,
    start && isValid(start) && format(start, 'EEE, d MMM yyyy, HH:mm'),
    parsed.duration_minutes && `${parsed.duration_minutes} min`,
  ].filter(Boolean)
  return (
    <div className="rounded-lg bg-secondary/40 px-3 py-2 text-sm">
      <p className="flex items-center gap-2 font-semibold">
        <SparklesIcon className="size-3.5" />
        Suggested from your text. Check every field marked “suggested”, then save.
      </p>
      {details.length > 0 && (
        <p className="text-muted-foreground">The text also mentions: {details.join(' · ')}</p>
      )}
      {replaces && <p className="text-muted-foreground">Saving replaces the current agenda.</p>}
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
      {agenda.from_ai && (
        <p className="flex items-center gap-1.5 text-xs text-muted-foreground">
          <SparklesIcon className="size-3" />
          Saved from a pasted agenda
        </p>
      )}
    </div>
  )
}

function Meta({ parts }: { parts: (string | number | null | undefined | false)[] }) {
  const text = parts.filter(Boolean).join(' · ')
  return text ? <span className="text-sm text-muted-foreground"> — {text}</span> : null
}
