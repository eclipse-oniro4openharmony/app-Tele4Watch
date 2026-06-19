import type { TdCallProtocolRequest } from '../td/TdRequestTypes';

const TDCALL_MIN_LAYER = 92;
const TDCALL_MAX_LAYER = 92;
// ADR-0009 / #65: 13.0.0 (tgcalls v2 signaling V3) is the protocol of the current
// production ecosystem (Web-K 2.2(657)+, Android 12.7.x); 4.0.0 stays declared as
// legacy fallback by product decision (#65#issuecomment-2760) — the native registry
// keeps InstanceV4_0_0Impl registered alongside InstanceV13_0_0Impl.
const TDCALL_LIBRARY_VERSIONS: string[] = [
  '4.0.0',
  '13.0.0'
];

/**
 * Builds the TDLib call protocol accepted by the local VoIP implementation.
 *
 * @returns TDLib `callProtocol` request payload.
 */
export function buildDefaultTdCallProtocolRequest(): TdCallProtocolRequest {
  return {
    '@type': 'callProtocol',
    'udp_p2p': true,
    'udp_reflector': true,
    'min_layer': TDCALL_MIN_LAYER,
    'max_layer': TDCALL_MAX_LAYER,
    'library_versions': TDCALL_LIBRARY_VERSIONS.slice()
  };
}
