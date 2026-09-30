/**
 * Zero-data-retention (ZDR) policy for Command Code models.
 *
 * Contributor and free models are offered in exchange for data usage, so the
 * `x-cmd-zdr: 1` header must not be sent for them. Command Code's model catalog
 * carries no free/ZDR flag, so this list is the single place to extend: add a
 * `RegExp` for a naming convention or a model id for an unmarked free model.
 */

export type ZdrExcludedModelMatcher = string | RegExp

export const ZDR_EXCLUDED_MODELS: readonly ZdrExcludedModelMatcher[] = [
  // Contributor models, e.g. meta/muse-spark-1.2-contributor.
  /contributor/i,
  // Free models with a name marker, e.g. poolside/laguna-s-2.1-free and
  // inclusionai/ling-3.1-flash:free.
  /(?:^|[:/-])free$/i,
  // Free models without a name marker. Keep in sync with the "Free models"
  // section of src/pricing.ts.
  "stealth/space-bunny-alpha",
]

export function isZdrExcludedModel(modelId: string): boolean {
  return ZDR_EXCLUDED_MODELS.some((matcher) =>
    typeof matcher === "string" ? matcher === modelId : matcher.test(modelId),
  )
}

/** ZDR headers for a model, or `undefined` when the model must not request ZDR. */
export function zdrHeadersForModel(
  modelId: string,
  headers: Record<string, string> | undefined,
): Record<string, string> | undefined {
  if (!headers || isZdrExcludedModel(modelId)) return undefined
  return headers
}
