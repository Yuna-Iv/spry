import { useEffect, useRef, useState } from 'react'
import { useSearchParams } from 'react-router'

import { AuthLayout, AuthNotConfigured } from '@/components/auth-layout'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { Button } from '@/components/ui/button'
import { authApi, authConfigured } from '@/lib/auth'

/**
 * /login sends the browser to Cognito's managed login page, which shows the email and
 * password form, sign-up and "Continue with Google". Cognito then redirects back here with
 * ?code=...; the Amplify OAuth listener (main.tsx) exchanges it for tokens, AuthProvider
 * picks up the user, and the GuestOnly route moves on to /home.
 */
export function LoginPage() {
  const [params] = useSearchParams()
  const returning = params.has('code')
  const cognitoError = params.get('error_description') ?? params.get('error')
  const [error, setError] = useState<string | null>(cognitoError)
  const started = useRef(false)

  const goToCognito = () => {
    setError(null)
    authApi.loginWithCognito().catch((e: Error) => setError(e.message))
  }

  useEffect(() => {
    // StrictMode runs effects twice in development; redirect only once.
    if (started.current || !authConfigured || returning || cognitoError) return
    started.current = true
    goToCognito()
  }, [returning, cognitoError])

  return (
    <AuthLayout
      title="Welcome back"
      subtitle="Sign in to see your meetings."
      footer="You will be sent to the sign-in page and back."
    >
      {!authConfigured && <AuthNotConfigured />}
      {error ? (
        <>
          <Alert variant="destructive">
            <AlertDescription>{error}</AlertDescription>
          </Alert>
          <Button className="w-full" onClick={goToCognito}>
            Try again
          </Button>
        </>
      ) : (
        <p className="text-center text-sm text-muted-foreground">
          {returning ? 'Signing you in...' : 'Redirecting to sign-in...'}
        </p>
      )}
    </AuthLayout>
  )
}
