/**
 * クライアントに返すエラーコード。
 * 詳細メッセージは Cloud Logging に、クライアントには種別のみ (security.md §10)。
 */
export type ApiErrorCode =
  | "INVALID_REQUEST"
  | "ID_CONFLICT"
  | "TRANSACTION_ALREADY_USED"
  | "TRANSACTION_INVALID"
  | "PAYLOAD_TOO_LARGE"
  | "TOO_MANY_REQUESTS"
  | "INTERNAL_ERROR";

export class ApiError extends Error {
  constructor(
    public readonly code: ApiErrorCode,
    public readonly status: number,
    message?: string,
  ) {
    super(message ?? code);
  }
}
