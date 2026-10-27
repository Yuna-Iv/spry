import { useEffect, useRef, useState } from 'react'
import { LoaderCircleIcon, SparklesIcon } from 'lucide-react'

import { Alert, AlertDescription } from '@/components/ui/alert'
import { Button } from '@/components/ui/button'
import { Textarea } from '@/components/ui/textarea'
import { ApiError, MAX_AGENDA_TEXT, parseAgenda, type ParseResult } from '@/lib/api'

type Props = {
  /** The parser's suggestion and the text it came from: the caller shows it in the agenda form. */
  onParsed: (result: ParseResult, sourceText: string) => void
  /** Back to the agenda, or straight to the empty form ("type it by hand"). */
  onCancel: () => void
  onTypeByHand: () => void
}

/** "Paste an agenda": text area, Parse, a progress message with Cancel, and clear errors. */
export function PasteAgenda({ onParsed, onCancel, onTypeByHand }: Props) {
  const [text, setText] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [pending, setPending] = useState(false)
  const [seconds, setSeconds] = useState(0)
  const controller = useRef<AbortController | null>(null)
  const tooLong = text.length > MAX_AGENDA_TEXT

  // Leaving the dialog mid-parse cancels the request.
  useEffect(() => () => controller.current?.abort(), [])

  useEffect(() => {
    if (!pending) return
    const timer = setInterval(() => setSeconds((s) => s + 1), 1000)
    return () => clearInterval(timer)
  }, [pending])

  const parse = async () => {
    const abort = new AbortController()
    controller.current = abort
    setError(null)
    setSeconds(0)
    setPending(true)
    try {
      const result = await parseAgenda(text, abort.signal)
      onParsed(result, text)
    } catch (e) {
      if (e instanceof DOMException && e.name === 'AbortError') return // the user cancelled
      setError(e instanceof ApiError ? e.message : 'Something went wrong. Try again.')
    } finally {
      if (controller.current === abort) controller.current = null
      setPending(false)
    }
  }

  const cancel = () => controller.current?.abort()

  return (
    <div className="flex flex-col gap-3">
      <Textarea
        aria-label="Pasted agenda"
        rows={6}
        value={text}
        disabled={pending}
        onChange={(e) => setText(e.target.value)}
        placeholder={
          'Paste an email, a chat message or notes, e.g.\n' +
          'Mon 10:00, pricing sync, 45 min. 1) new Pro prices — Olena, 15 min 2) customer feedback — Taras'
        }
      />
      <p className={tooLong ? 'text-sm text-destructive' : 'text-xs text-muted-foreground'}>
        {text.length.toLocaleString('en')} / {MAX_AGENDA_TEXT.toLocaleString('en')} characters
        {tooLong && ': too long to parse'}
      </p>

      {error && (
        <Alert variant="destructive">
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}

      {pending ? (
        <div className="flex items-center justify-between gap-2" role="status" aria-live="polite">
          <span className="flex items-center gap-2 text-sm text-muted-foreground">
            <LoaderCircleIcon className="size-4 animate-spin" />
            Reading your agenda… {seconds} s (usually 2–8 s)
          </span>
          <Button type="button" variant="outline" size="sm" onClick={cancel}>
            Cancel
          </Button>
        </div>
      ) : (
        <div className="flex flex-wrap items-center justify-between gap-2">
          <Button type="button" variant="link" className="px-0" onClick={onTypeByHand}>
            Type it by hand instead
          </Button>
          <div className="flex gap-2">
            <Button type="button" variant="outline" onClick={onCancel}>
              Back
            </Button>
            <Button type="button" disabled={!text.trim() || tooLong} onClick={parse}>
              <SparklesIcon />
              Parse
            </Button>
          </div>
        </div>
      )}
    </div>
  )
}
