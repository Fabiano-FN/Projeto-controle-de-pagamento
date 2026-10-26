export interface PasswordCheckResult {
  minLength: boolean;
  hasUppercase: boolean;
  hasLowercase: boolean;
  hasNumber: boolean;
  hasSymbol: boolean;
  matchesConfirmation: boolean;
  isValid: boolean;
}

/**
 * Valida a Regra 3B:
 * - Mínimo de 8 caracteres
 * - Pelo menos 1 letra maiúscula (A-Z)
 * - Pelo menos 1 letra minúscula (a-z)
 * - Pelo menos 1 número (0-9)
 * - Pelo menos 1 símbolo especial (!@#$%^&*(),.?":{}|<>_-+=~`/[]\;)
 * - Confirmação de senha idêntica
 */
export function evaluatePasswordStrength(
  password: string,
  confirmPassword: string
): PasswordCheckResult {
  const minLength = password.length >= 8;
  const hasUppercase = /[A-Z]/.test(password);
  const hasLowercase = /[a-z]/.test(password);
  const hasNumber = /[0-9]/.test(password);
  const hasSymbol = /[^A-Za-z0-9]/.test(password);
  const matchesConfirmation =
    password.length > 0 && password === confirmPassword;

  return {
    minLength,
    hasUppercase,
    hasLowercase,
    hasNumber,
    hasSymbol,
    matchesConfirmation,
    isValid:
      minLength &&
      hasUppercase &&
      hasLowercase &&
      hasNumber &&
      hasSymbol &&
      matchesConfirmation,
  };
}

