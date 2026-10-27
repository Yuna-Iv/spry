import { zodResolver } from '@hookform/resolvers/zod'
import { PlusIcon, XIcon } from 'lucide-react'
import { Controller, useFieldArray, useForm, type FieldPath } from 'react-hook-form'
import { toast } from 'sonner'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { FieldError } from '@/components/ui/field'
import { Input } from '@/components/ui/input'
import { useSaveAgenda } from '@/hooks/queries'
import {
  agendaSchema,
  emptyActionItem,
  emptyItem,
  toPayload,
  type AgendaFormValues,
} from '@/lib/agenda'
import type { AiSuggestion } from '@/lib/api'
import { cn } from '@/lib/utils'

type Props = {
  meetingId: string
  initialValues: AgendaFormValues
  /**
   * Set when the values came from the agenda parser: every filled field the user has not
   * touched yet is marked "suggested", and the suggestion is saved next to the agenda.
   */
  suggestion?: AiSuggestion | null
  onCancel: () => void
  onSaved: () => void
}

export function AgendaForm({ meetingId, initialValues, suggestion, onCancel, onSaved }: Props) {
  const saveAgenda = useSaveAgenda()
  const form = useForm<AgendaFormValues>({
    resolver: zodResolver(agendaSchema),
    defaultValues: initialValues,
  })
  const items = useFieldArray({ control: form.control, name: 'items' })
  const actionItems = useFieldArray({ control: form.control, name: 'actionItems' })

  /** A field the model filled in and the user has not changed yet. */
  const isSuggested = (name: FieldPath<AgendaFormValues>) =>
    Boolean(suggestion) &&
    !form.getFieldState(name, form.formState).isDirty &&
    String(form.getValues(name) ?? '') !== ''

  const onSubmit = form.handleSubmit((values) => {
    saveAgenda.mutate(
      { meetingId, ...toPayload(values), ai_suggestion: suggestion ?? null },
      {
        onSuccess: () => {
          toast.success('Agenda saved')
          onSaved()
        },
        onError: (error) => form.setError('root', { message: error.message }),
      },
    )
  })

  return (
    <form onSubmit={onSubmit} noValidate className="flex flex-col gap-5">
      <fieldset className="flex flex-col gap-3">
        <legend className="mb-2 text-sm font-semibold">Topics</legend>
        {items.fields.length === 0 && (
          <p className="text-sm text-muted-foreground">No topics yet.</p>
        )}
        {items.fields.map((row, index) => (
          <div key={row.id} className="flex flex-col gap-2 rounded-lg border p-3">
            <Controller
              name={`items.${index}.topic`}
              control={form.control}
              render={({ field, fieldState }) => (
                <div>
                  <SuggestedInput
                    suggested={isSuggested(field.name)}
                    placeholder="Topic"
                    aria-label={`Topic ${index + 1}`}
                    aria-invalid={fieldState.invalid}
                    {...field}
                  />
                  <FieldError errors={[fieldState.error]} />
                </div>
              )}
            />
            <div className="grid grid-cols-[1fr_7rem_auto] items-start gap-2">
              <Controller
                name={`items.${index}.owner`}
                control={form.control}
                render={({ field }) => (
                  <SuggestedInput
                    suggested={isSuggested(field.name)}
                    placeholder="Owner (optional)"
                    aria-label={`Owner of topic ${index + 1}`}
                    {...field}
                  />
                )}
              />
              <Controller
                name={`items.${index}.minutes`}
                control={form.control}
                render={({ field, fieldState }) => (
                  <div>
                    <SuggestedInput
                      suggested={isSuggested(field.name)}
                      inputMode="numeric"
                      placeholder="Min"
                      aria-label={`Minutes for topic ${index + 1}`}
                      aria-invalid={fieldState.invalid}
                      {...field}
                    />
                    <FieldError errors={[fieldState.error]} />
                  </div>
                )}
              />
              <Button
                type="button"
                variant="ghost"
                size="icon"
                aria-label={`Remove topic ${index + 1}`}
                onClick={() => items.remove(index)}
              >
                <XIcon />
              </Button>
            </div>
          </div>
        ))}
        <Button
          type="button"
          variant="outline"
          size="sm"
          className="self-start"
          onClick={() => items.append(emptyItem)}
        >
          <PlusIcon />
          Add topic
        </Button>
      </fieldset>

      <fieldset className="flex flex-col gap-3">
        <legend className="mb-2 text-sm font-semibold">Action items</legend>
        {actionItems.fields.map((row, index) => (
          <div key={row.id} className="flex flex-col gap-2 rounded-lg border p-3">
            <Controller
              name={`actionItems.${index}.task`}
              control={form.control}
              render={({ field, fieldState }) => (
                <div>
                  <SuggestedInput
                    suggested={isSuggested(field.name)}
                    placeholder="Task"
                    aria-label={`Action item ${index + 1}`}
                    aria-invalid={fieldState.invalid}
                    {...field}
                  />
                  <FieldError errors={[fieldState.error]} />
                </div>
              )}
            />
            <div className="grid grid-cols-[1fr_10rem_auto] items-start gap-2">
              <Controller
                name={`actionItems.${index}.owner`}
                control={form.control}
                render={({ field }) => (
                  <SuggestedInput
                    suggested={isSuggested(field.name)}
                    placeholder="Owner (optional)"
                    aria-label={`Owner of action item ${index + 1}`}
                    {...field}
                  />
                )}
              />
              <Controller
                name={`actionItems.${index}.due`}
                control={form.control}
                render={({ field }) => (
                  <SuggestedInput
                    suggested={isSuggested(field.name)}
                    type="date"
                    aria-label={`Due date of action item ${index + 1}`}
                    {...field}
                  />
                )}
              />
              <Button
                type="button"
                variant="ghost"
                size="icon"
                aria-label={`Remove action item ${index + 1}`}
                onClick={() => actionItems.remove(index)}
              >
                <XIcon />
              </Button>
            </div>
          </div>
        ))}
        <Button
          type="button"
          variant="outline"
          size="sm"
          className="self-start"
          onClick={() => actionItems.append(emptyActionItem)}
        >
          <PlusIcon />
          Add action item
        </Button>
      </fieldset>

      {form.formState.errors.root && <FieldError>{form.formState.errors.root.message}</FieldError>}

      <div className="flex justify-end gap-2">
        <Button type="button" variant="outline" onClick={onCancel}>
          Cancel
        </Button>
        <Button type="submit" disabled={saveAgenda.isPending}>
          {saveAgenda.isPending ? 'Saving...' : 'Save agenda'}
        </Button>
      </div>
    </form>
  )
}

/**
 * An input marked "suggested" (a tinted background and a small badge on its top border, so it
 * never covers the value) while its value is still the model's.
 */
function SuggestedInput({
  suggested,
  className,
  ...props
}: React.ComponentProps<typeof Input> & { suggested: boolean }) {
  return (
    <div className="relative">
      <Input className={cn(suggested && 'bg-secondary/40', className)} {...props} />
      {suggested && (
        <Badge
          variant="outline"
          className="pointer-events-none absolute -top-2 right-4 h-4 bg-background px-1.5 text-[10px]"
        >
          suggested
        </Badge>
      )}
    </div>
  )
}
