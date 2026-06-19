#include "v2/InstanceNetworking.h"

namespace tgcalls {

InstanceNetworking::ConnectionDescription::CandidateDescription InstanceNetworking::connectionDescriptionFromCandidate(
    cricket::Candidate const &candidate) {
    InstanceNetworking::ConnectionDescription::CandidateDescription result;

    result.type = candidate.type();
    result.protocol = candidate.protocol();
    result.address = candidate.address().ToString();

    return result;
}

} // namespace tgcalls
