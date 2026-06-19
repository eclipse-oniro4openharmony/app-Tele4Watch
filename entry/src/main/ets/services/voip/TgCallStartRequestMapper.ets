import type { TgCallStartRequest } from 'tgcall';
import type {
  TdParsedCallPayload,
  TdParsedCallServerPayload,
  TdParsedCallStatePayload
} from '../td/TdPayloadTypes';

export type TgCallStartRequestMapError =
  'notReady' |
  'missingEncryptionKey' |
  'missingServers' |
  'missingProtocolVersion';

export interface TgCallStartRequestMapResult {
  'ok': boolean;
  'request'?: TgCallStartRequest;
  'error'?: TgCallStartRequestMapError;
}

// Preference order when TDLib's intersection offers more than one common version
// (ADR-0009): 13.0.0 first — the only version spoken by the current production
// ecosystem (Web-K, Android) — then 4.0.0 as the legacy Web-K fallback
// (#65#issuecomment-2760). ADR-0004's interop table documents the matrix.
const PREFERRED_PROTOCOL_VERSIONS: string[] = ['13.0.0', '4.0.0'];

function cloneServer(server: TdParsedCallServerPayload): TdParsedCallServerPayload {
  const clonedServer: TdParsedCallServerPayload = {
    'id': server.id,
    'ipAddress': server.ipAddress,
    'ipv6Address': server.ipv6Address,
    'port': server.port,
    'type': server.type
  };
  if (server.peerTag !== undefined) {
    clonedServer.peerTag = server.peerTag;
  }
  if (server.username !== undefined) {
    clonedServer.username = server.username;
  }
  if (server.password !== undefined) {
    clonedServer.password = server.password;
  }
  if (server.supportsTurn !== undefined) {
    clonedServer.supportsTurn = server.supportsTurn;
  }
  if (server.supportsStun !== undefined) {
    clonedServer.supportsStun = server.supportsStun;
  }
  return clonedServer;
}

function cloneServers(servers: TdParsedCallServerPayload[]): TdParsedCallServerPayload[] {
  const clonedServers: TdParsedCallServerPayload[] = [];
  for (const server of servers) {
    // Keep the serialized native payload explicit and stable under ArkTS nominal typing.
    clonedServers.push(cloneServer(server));
  }
  return clonedServers;
}

function containsProtocolVersion(versions: string[], expectedVersion: string): boolean {
  for (const version of versions) {
    if (version === expectedVersion) {
      return true;
    }
  }
  return false;
}

function selectProtocolVersion(state: TdParsedCallStatePayload, supportedVersions: string[]): string {
  if (state.protocol === undefined) {
    return '';
  }
  for (const preferredVersion of PREFERRED_PROTOCOL_VERSIONS) {
    for (const version of state.protocol.libraryVersions) {
      if (version.trim() === preferredVersion) {
        return preferredVersion;
      }
    }
  }
  if (supportedVersions.length > 0) {
    for (const version of state.protocol.libraryVersions) {
      const safeVersion = version.trim();
      if (safeVersion.length > 0 && containsProtocolVersion(supportedVersions, safeVersion)) {
        return safeVersion;
      }
    }
  }
  for (const version of state.protocol.libraryVersions) {
    const safeVersion = version.trim();
    if (safeVersion.length > 0) {
      return safeVersion;
    }
  }
  return '';
}

/**
 * Maps TDLib `callStateReady` parameters into the native tgcall start request.
 *
 * @param call Normalized TDLib call emitted by `TdClient`.
 * @param supportedVersions Native tgcall protocol versions that can start a real media instance.
 * @returns Mapping result with a native tgcall request or a stable rejection reason.
 */
export function mapReadyCallToTgCallStartRequest(
  call: TdParsedCallPayload,
  supportedVersions?: string[]
): TgCallStartRequestMapResult {
  const state: TdParsedCallStatePayload = call.state;
  if (state.kind !== 'ready') {
    return {
      'ok': false,
      'error': 'notReady'
    };
  }

  const encryptionKey = state.encryptionKey;
  if (encryptionKey === undefined || encryptionKey.trim().length === 0) {
    return {
      'ok': false,
      'error': 'missingEncryptionKey'
    };
  }

  if (state.servers === undefined || state.servers.length === 0) {
    return {
      'ok': false,
      'error': 'missingServers'
    };
  }

  const protocolVersion = selectProtocolVersion(state, supportedVersions === undefined ? [] : supportedVersions);
  if (protocolVersion.length === 0) {
    return {
      'ok': false,
      'error': 'missingProtocolVersion'
    };
  }

  const request: TgCallStartRequest = {
    'protocolVersion': protocolVersion,
    'serversJson': JSON.stringify(cloneServers(state.servers)),
    'encryptionKeyBase64': encryptionKey,
    'isOutgoing': call.isOutgoing,
    'allowP2p': state.allowP2p === true,
    'customParameters': state.customParameters === undefined ? '' : state.customParameters
  };
  return {
    'ok': true,
    'request': request
  };
}
