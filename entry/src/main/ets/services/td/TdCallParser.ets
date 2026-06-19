import {
  TdCallDiscardReasonPayload,
  TdCallIdPayload,
  TdCallPayload,
  TdCallProtocolPayload,
  TdCallServerPayload,
  TdCallServerTypePayload,
  TdCallStatePayload,
  TdChatId,
  TdErrorPayload,
  TdIntValue,
  TdParsedCallPayload,
  TdParsedCallProtocolPayload,
  TdParsedCallServerPayload,
  TdParsedCallStateKind,
  TdParsedCallStatePayload,
  TdUpdateCallPayload,
  TdUpdateNewCallSignalingDataPayload
} from './TdPayloadTypes';
import { extractExtra } from './TdPayloadParsers';

/**
 * Result of parsing `updateCall` payload.
 */
export interface TdParsedUpdateCallResult {
  /** Whether payload was parsed and contains a usable call. */
  'ok': boolean;
  /** Parsed normalized call payload. */
  'call'?: TdParsedCallPayload;
  /** Parsing error text (only set for malformed JSON payloads). */
  'error'?: string;
}

/**
 * Result of parsing `updateNewCallSignalingData` payload.
 */
export interface TdParsedUpdateNewCallSignalingDataResult {
  /** Whether payload was parsed and contains call id and signaling data. */
  'ok': boolean;
  /** TDLib call id. */
  'callId'?: number;
  /** Opaque TDLib signaling data payload. */
  'data'?: string;
  /** Parsing error text (only set for malformed JSON payloads). */
  'error'?: string;
}

/**
 * Result of parsing a TDLib `callId` payload returned by `createCall`.
 */
export interface TdParsedCallIdResult {
  /** Whether payload was parsed and contains a usable call id. */
  'ok': boolean;
  /** TDLib call id. */
  'callId'?: number;
  /** Request correlation token echoed back by TDLib. */
  'extra'?: string;
  /** Parsing error text (only set for malformed JSON payloads). */
  'error'?: string;
}

/**
 * Reads TDLib `@type` from payload variants that expose it.
 *
 * @param value Parsed TDLib payload that may contain `@type`.
 * @returns Type string or empty string when unavailable.
 */
function readPayloadType(
  value: TdCallStatePayload | TdCallServerTypePayload | TdCallDiscardReasonPayload | TdErrorPayload | undefined
): string {
  if (!value) {
    return '';
  }
  const serialized = JSON.stringify(value);
  const match = serialized.match(/\"@type\"\s*:\s*\"([^\"]+)\"/);
  if (!match || match.length < 2) {
    return '';
  }
  return match[1];
}

/**
 * Reads TDLib id-like value as non-empty string.
 *
 * @param value TDLib id represented as number or string.
 * @returns Id string or empty string when value is invalid.
 */
function parseIdString(value: TdChatId | TdIntValue | undefined): string {
  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (trimmed.length > 0) {
      return trimmed;
    }
    return '';
  }
  if (typeof value === 'number' && value !== 0) {
    return String(Math.trunc(value));
  }
  return '';
}

/**
 * Normalizes a TDLib integer-like value to positive number.
 *
 * @param value Number or numeric string from TDLib payload.
 * @returns Positive integer or `0` when invalid.
 */
function parsePositiveInt(value: TdIntValue | undefined): number {
  if (typeof value === 'number' && value > 0) {
    return Math.trunc(value);
  }
  if (typeof value === 'string' && value.length > 0) {
    const parsed = Number.parseInt(value, 10);
    if (!Number.isNaN(parsed) && parsed > 0) {
      return parsed;
    }
  }
  return 0;
}

/**
 * Normalizes a TDLib integer-like value to non-negative number.
 *
 * @param value Number or numeric string from TDLib payload.
 * @returns Non-negative integer or `0` when invalid.
 */
function parseNonNegativeInt(value: TdIntValue | undefined): number {
  if (typeof value === 'number' && value >= 0) {
    return Math.trunc(value);
  }
  if (typeof value === 'string' && value.length > 0) {
    const parsed = Number.parseInt(value, 10);
    if (!Number.isNaN(parsed) && parsed >= 0) {
      return parsed;
    }
  }
  return 0;
}

function parseStringArray(value: string[] | undefined): string[] {
  const result: string[] = [];
  if (!Array.isArray(value)) {
    return result;
  }
  for (const item of value) {
    if (typeof item !== 'string') {
      continue;
    }
    result.push(item);
  }
  return result;
}

function mapCallStateKind(tdType: string): TdParsedCallStateKind | undefined {
  if (tdType === 'callStatePending') {
    return 'pending';
  }
  if (tdType === 'callStateExchangingKeys') {
    return 'exchangingKeys';
  }
  if (tdType === 'callStateReady') {
    return 'ready';
  }
  if (tdType === 'callStateHangingUp') {
    return 'hangingUp';
  }
  if (tdType === 'callStateDiscarded') {
    return 'discarded';
  }
  if (tdType === 'callStateError') {
    return 'error';
  }
  return undefined;
}

function parseProtocol(protocol: TdCallProtocolPayload | undefined): TdParsedCallProtocolPayload | undefined {
  if (!protocol) {
    return undefined;
  }

  return {
    'udpP2p': protocol.udp_p2p === true,
    'udpReflector': protocol.udp_reflector === true,
    'minLayer': parseNonNegativeInt(protocol.min_layer),
    'maxLayer': parseNonNegativeInt(protocol.max_layer),
    'libraryVersions': parseStringArray(protocol.library_versions)
  };
}

function parseServer(server: TdCallServerPayload): TdParsedCallServerPayload | undefined {
  const id = parseIdString(server.id);
  const port = parsePositiveInt(server.port);
  if (id.length === 0 || port <= 0) {
    return undefined;
  }

  const typePayload = server.type;
  const parsedServer: TdParsedCallServerPayload = {
    'id': id,
    'ipAddress': typeof server.ip_address === 'string' ? server.ip_address : '',
    'ipv6Address': typeof server.ipv6_address === 'string' ? server.ipv6_address : '',
    'port': port,
    'type': readPayloadType(typePayload)
  };
  if (typePayload && typeof typePayload.peer_tag === 'string' && typePayload.peer_tag.length > 0) {
    parsedServer.peerTag = typePayload.peer_tag;
  }
  if (typePayload && typeof typePayload.username === 'string' && typePayload.username.length > 0) {
    parsedServer.username = typePayload.username;
  }
  if (typePayload && typeof typePayload.password === 'string' && typePayload.password.length > 0) {
    parsedServer.password = typePayload.password;
  }
  if (typePayload && typeof typePayload.supports_turn === 'boolean') {
    parsedServer.supportsTurn = typePayload.supports_turn;
  }
  if (typePayload && typeof typePayload.supports_stun === 'boolean') {
    parsedServer.supportsStun = typePayload.supports_stun;
  }
  return parsedServer;
}

function parseServers(servers: TdCallServerPayload[] | undefined): TdParsedCallServerPayload[] {
  const result: TdParsedCallServerPayload[] = [];
  if (!Array.isArray(servers)) {
    return result;
  }
  for (const server of servers) {
    const parsedServer = parseServer(server);
    if (parsedServer) {
      result.push(parsedServer);
    }
  }
  return result;
}

function parseCallState(state: TdCallStatePayload | undefined): TdParsedCallStatePayload | undefined {
  if (!state) {
    return undefined;
  }

  const tdType = readPayloadType(state);
  const kind = mapCallStateKind(tdType);
  if (!kind) {
    return undefined;
  }

  const parsedState: TdParsedCallStatePayload = {
    'kind': kind,
    'tdType': tdType
  };
  if (kind === 'pending') {
    parsedState.isCreated = state.is_created === true;
    parsedState.isReceived = state.is_received === true;
  }
  if (kind === 'ready') {
    const protocol = parseProtocol(state.protocol);
    if (protocol) {
      parsedState.protocol = protocol;
    }
    parsedState.servers = parseServers(state.servers);
    if (typeof state.config === 'string') {
      parsedState.config = state.config;
    }
    if (typeof state.encryption_key === 'string') {
      parsedState.encryptionKey = state.encryption_key;
    }
    parsedState.emojis = parseStringArray(state.emojis);
    if (typeof state.allow_p2p === 'boolean') {
      parsedState.allowP2p = state.allow_p2p;
    }
    if (typeof state.is_group_call_supported === 'boolean') {
      parsedState.isGroupCallSupported = state.is_group_call_supported;
    }
    if (typeof state.custom_parameters === 'string') {
      parsedState.customParameters = state.custom_parameters;
    }
  }
  if (kind === 'discarded') {
    parsedState.discardReason = readPayloadType(state.reason);
    parsedState.needRating = state.need_rating === true;
    parsedState.needDebugInformation = state.need_debug_information === true;
    parsedState.needLog = state.need_log === true;
  }
  if (kind === 'error' && state.error) {
    parsedState.errorCode = parseNonNegativeInt(state.error.code);
    parsedState.errorMessage = typeof state.error.message === 'string' ? state.error.message : '';
  }
  return parsedState;
}

function parseCall(call: TdCallPayload | undefined): TdParsedCallPayload | undefined {
  if (!call) {
    return undefined;
  }

  const callId = parsePositiveInt(call.id);
  const userId = parseIdString(call.user_id);
  const state = parseCallState(call.state);
  if (callId <= 0 || userId.length === 0 || !state) {
    return undefined;
  }

  return {
    'id': callId,
    'uniqueId': parseIdString(call.unique_id),
    'userId': userId,
    'isOutgoing': call.is_outgoing === true,
    'isVideo': call.is_video === true,
    'state': state
  };
}

/**
 * Parses TDLib payload that should contain `updateCall`.
 *
 * @param payload Raw TDLib JSON payload.
 * @returns Structured parser result with normalized call payload.
 */
export function parseUpdateCall(payload: string): TdParsedUpdateCallResult {
  try {
    const parsed = JSON.parse(payload) as TdUpdateCallPayload;
    const call = parseCall(parsed.call);
    if (!call) {
      return { 'ok': false };
    }
    return {
      'ok': true,
      'call': call
    };
  } catch (error) {
    return {
      'ok': false,
      'error': String(error)
    };
  }
}

/**
 * Parses TDLib payload that should contain a `callId` returned by `createCall`.
 *
 * @param payload Raw TDLib JSON payload.
 * @returns Structured parser result with call id and request correlation token.
 */
export function parseCallId(payload: string): TdParsedCallIdResult {
  try {
    const parsed = JSON.parse(payload) as TdCallIdPayload;
    const callId = parsePositiveInt(parsed.id);
    if (callId <= 0) {
      return { 'ok': false };
    }
    return {
      'ok': true,
      'callId': callId,
      'extra': extractExtra(payload)
    };
  } catch (error) {
    return {
      'ok': false,
      'error': String(error)
    };
  }
}

/**
 * Parses TDLib payload that should contain `updateNewCallSignalingData`.
 *
 * @param payload Raw TDLib JSON payload.
 * @returns Structured parser result with call id and signaling data.
 */
export function parseUpdateNewCallSignalingData(payload: string): TdParsedUpdateNewCallSignalingDataResult {
  try {
    const parsed = JSON.parse(payload) as TdUpdateNewCallSignalingDataPayload;
    const callId = parsePositiveInt(parsed.call_id);
    if (callId <= 0 || typeof parsed.data !== 'string') {
      return { 'ok': false };
    }
    return {
      'ok': true,
      'callId': callId,
      'data': parsed.data
    };
  } catch (error) {
    return {
      'ok': false,
      'error': String(error)
    };
  }
}
