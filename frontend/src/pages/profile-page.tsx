import { zodResolver } from '@hookform/resolvers/zod'
import { useState } from 'react'
import { Controller, useForm } from 'react-hook-form'
import { Link } from 'react-router'
import { z } from 'zod'

import { AuthLayout, PasswordInput } from '@/components/auth-layout'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { Button } from '@/components/ui/button'
import { Field, FieldError, FieldGroup, FieldLabel } from '@/components/ui/field'
import { useAuth, useChangePassword } from '@/lib/auth'

const passwordSchema = z.object({
  currentPassword: z.string().min(1, 'Enter your current password'),
  newPassword: z.string().min(8, 'At least 8 characters'),
})

type PasswordValues = z.infer<typeof passwordSchema>

export function ProfilePage() {
  const { user, signOut } = useAuth()
  const changePassword = useChangePassword()
  const [saved, setSaved] = useState(false)
  const form = useForm<PasswordValues>({
    resolver: zodResolver(passwordSchema),
    defaultValues: { currentPassword: '', newPassword: '' },
  })

  const onSubmit = form.handleSubmit((values) => {
    setSaved(false)
    changePassword.mutate(values, {
      onSuccess: () => {
        setSaved(true)
        form.reset()
      },
      onError: (error) => form.setError('root', { message: error.message }),
    })
  })

  if (!user) return null

  return (
    <AuthLayout
      title={user.name}
      subtitle={user.email}
      footer={
        <Link to="/home" className="underline underline-offset-4">
          Back to meetings
        </Link>
      }
    >
      {user.provider === 'password' ? (
        <form onSubmit={onSubmit} noValidate>
          <FieldGroup>
            {form.formState.errors.root && (
              <Alert variant="destructive">
                <AlertDescription>{form.formState.errors.root.message}</AlertDescription>
              </Alert>
            )}
            {saved && (
              <Alert>
                <AlertDescription>Password changed</AlertDescription>
              </Alert>
            )}
            <Controller
              name="currentPassword"
              control={form.control}
              render={({ field, fieldState }) => (
                <Field data-invalid={fieldState.invalid}>
                  <FieldLabel htmlFor="current-password">Current password</FieldLabel>
                  <PasswordInput
                    {...field}
                    id="current-password"
                    autoComplete="current-password"
                    aria-invalid={fieldState.invalid}
                  />
                  {fieldState.invalid && <FieldError errors={[fieldState.error]} />}
                </Field>
              )}
            />
            <Controller
              name="newPassword"
              control={form.control}
              render={({ field, fieldState }) => (
                <Field data-invalid={fieldState.invalid}>
                  <FieldLabel htmlFor="new-password">New password</FieldLabel>
                  <PasswordInput
                    {...field}
                    id="new-password"
                    autoComplete="new-password"
                    aria-invalid={fieldState.invalid}
                  />
                  {fieldState.invalid && <FieldError errors={[fieldState.error]} />}
                </Field>
              )}
            />
            <Button type="submit" className="w-full" disabled={changePassword.isPending}>
              Change password
            </Button>
          </FieldGroup>
        </form>
      ) : (
        <p className="text-center text-sm text-muted-foreground">Signed in with Google.</p>
      )}
      <Button variant="outline" className="w-full" onClick={signOut}>
        Sign out
      </Button>
    </AuthLayout>
  )
}
