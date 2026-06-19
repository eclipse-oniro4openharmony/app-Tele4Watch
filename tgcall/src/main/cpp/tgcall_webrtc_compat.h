#pragma once

#include "api/scoped_refptr.h"

namespace webrtc {

template <typename T>
using scoped_refptr = rtc::scoped_refptr<T>;

}  // namespace webrtc
