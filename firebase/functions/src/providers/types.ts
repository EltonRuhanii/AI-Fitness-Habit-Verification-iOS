/**
 * A vision model that answers the structured criteria prompt. Implementations must not
 * decide the verdict — they return the model's raw text, which `policy.ts` parses and decides.
 * Swap providers by implementing this interface; nothing else changes.
 */
export interface VisionProvider {
  readonly name: string;
  readonly model: string;
  assess(request: VisionRequest): Promise<VisionResponse>;
}

export interface VisionRequest {
  image: Buffer;
  mediaType: "image/jpeg";
  system: string;
  userText: string;
  schema: Record<string, unknown>;
}

export interface VisionResponse {
  text: string;
  /** Model that actually produced the answer (may differ from the requested one after a fallback). */
  model: string;
}

export type ProviderErrorCode = "timeout" | "rate_limited" | "refusal" | "provider_error";

export class ProviderError extends Error {
  constructor(readonly code: ProviderErrorCode, message: string) {
    super(message);
  }
}
