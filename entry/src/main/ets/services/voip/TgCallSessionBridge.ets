import type { TgCallStartRequest } from 'tgcall';

export interface TgCallSessionBridge {
  'getSupportedVersions': () => string[];
  'startCall': (
    request: TgCallStartRequest,
    onSignalingData: (instanceId: number) => void,
    onAudioLevel: (level: number) => void
  ) => number;
  'startDiagnosticCall': (request: TgCallStartRequest) => number;
  'feedSignalingData': (instanceId: number, dataBase64: string) => void;
  'drainSignalingData': (instanceId: number) => string[];
  'setMuteMicrophone': (instanceId: number, muted: boolean) => void;
  'stopCall': (instanceId: number) => void;
}
