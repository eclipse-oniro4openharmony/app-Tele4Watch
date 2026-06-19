#include "VideoCaptureInterfaceImpl.h"

#include "StaticThreads.h"
#include "VideoCapturerInterface.h"

#include <utility>

namespace tgcalls {

VideoCaptureInterfaceObject::VideoCaptureInterfaceObject(
    std::string,
    bool isScreenCapture,
    std::shared_ptr<PlatformContext> platformContext,
    Threads &)
    : _platformContext(std::move(platformContext)),
      _isScreenCapture(isScreenCapture) {
}

VideoCaptureInterfaceObject::~VideoCaptureInterfaceObject() = default;

webrtc::scoped_refptr<webrtc::VideoTrackSourceInterface> VideoCaptureInterfaceObject::source() {
  return nullptr;
}

int VideoCaptureInterfaceObject::getRotation() {
  return 0;
}

bool VideoCaptureInterfaceObject::isScreenCapture() {
  return _isScreenCapture;
}

void VideoCaptureInterfaceObject::switchToDevice(std::string, bool isScreenCapture) {
  _isScreenCapture = isScreenCapture;
}

void VideoCaptureInterfaceObject::withNativeImplementation(std::function<void(void *)> completion) {
  completion(nullptr);
}

void VideoCaptureInterfaceObject::setState(VideoState state) {
  _state = state;
  if (_stateUpdated) {
    _stateUpdated(state);
  }
}

void VideoCaptureInterfaceObject::setPreferredAspectRatio(float aspectRatio) {
  _preferredAspectRatio = aspectRatio;
}

void VideoCaptureInterfaceObject::setOutput(std::shared_ptr<rtc::VideoSinkInterface<webrtc::VideoFrame>> sink) {
  _currentUncroppedSink = sink;
}

void VideoCaptureInterfaceObject::setStateUpdated(std::function<void(VideoState)> stateUpdated) {
  _stateUpdated = std::move(stateUpdated);
}

void VideoCaptureInterfaceObject::setRotationUpdated(std::function<void(int)> rotationUpdated) {
  _rotationUpdated = std::move(rotationUpdated);
}

void VideoCaptureInterfaceObject::setOnFatalError(std::function<void()> error) {
  _onFatalError = std::move(error);
}

void VideoCaptureInterfaceObject::setOnPause(std::function<void(bool)> pause) {
  _onPause = std::move(pause);
}

void VideoCaptureInterfaceObject::setOnIsActiveUpdated(std::function<void(bool)> onIsActiveUpdated) {
  _onIsActiveUpdated = std::move(onIsActiveUpdated);
}

void VideoCaptureInterfaceObject::updateAspectRateAdaptation() {
}

VideoCaptureInterfaceImpl::VideoCaptureInterfaceImpl(
    std::string deviceId,
    bool isScreenCapture,
    std::shared_ptr<PlatformContext> platformContext,
    std::shared_ptr<Threads> threads)
    : _impl(threads->getMediaThread(), [deviceId, isScreenCapture, platformContext, threads]() {
        return std::make_shared<VideoCaptureInterfaceObject>(deviceId, isScreenCapture, platformContext, *threads);
      }) {
}

VideoCaptureInterfaceImpl::~VideoCaptureInterfaceImpl() = default;

void VideoCaptureInterfaceImpl::switchToDevice(std::string deviceId, bool isScreenCapture) {
  _impl.perform([deviceId, isScreenCapture](VideoCaptureInterfaceObject *impl) {
    impl->switchToDevice(deviceId, isScreenCapture);
  });
}

void VideoCaptureInterfaceImpl::withNativeImplementation(std::function<void(void *)> completion) {
  _impl.perform([completion](VideoCaptureInterfaceObject *impl) {
    impl->withNativeImplementation(completion);
  });
}

void VideoCaptureInterfaceImpl::setState(VideoState state) {
  _impl.perform([state](VideoCaptureInterfaceObject *impl) {
    impl->setState(state);
  });
}

void VideoCaptureInterfaceImpl::setPreferredAspectRatio(float aspectRatio) {
  _impl.perform([aspectRatio](VideoCaptureInterfaceObject *impl) {
    impl->setPreferredAspectRatio(aspectRatio);
  });
}

void VideoCaptureInterfaceImpl::setOutput(std::shared_ptr<rtc::VideoSinkInterface<webrtc::VideoFrame>> sink) {
  _impl.perform([sink](VideoCaptureInterfaceObject *impl) {
    impl->setOutput(sink);
  });
}

void VideoCaptureInterfaceImpl::setOnFatalError(std::function<void()> error) {
  _impl.perform([error](VideoCaptureInterfaceObject *impl) {
    impl->setOnFatalError(error);
  });
}

void VideoCaptureInterfaceImpl::setOnPause(std::function<void(bool)> pause) {
  _impl.perform([pause](VideoCaptureInterfaceObject *impl) {
    impl->setOnPause(pause);
  });
}

void VideoCaptureInterfaceImpl::setOnIsActiveUpdated(std::function<void(bool)> onIsActiveUpdated) {
  _impl.perform([onIsActiveUpdated](VideoCaptureInterfaceObject *impl) {
    impl->setOnIsActiveUpdated(onIsActiveUpdated);
  });
}

ThreadLocalObject<VideoCaptureInterfaceObject> *VideoCaptureInterfaceImpl::object() {
  return &_impl;
}

}  // namespace tgcalls
