//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2025 Jellyfin & Jellyfin Contributors
//

import Defaults
import Factory
import Foundation
import JellyfinAPI
import Logging

extension BaseItemDto {

    func videoPlayerViewModel(with mediaSource: MediaSourceInfo) async throws -> VideoPlayerViewModel {

        let currentVideoPlayerType = Defaults[.VideoPlayer.videoPlayerType]
        let currentVideoBitrate = Defaults[.VideoPlayer.Playback.appMaximumBitrate]
        let compatibilityMode = Defaults[.VideoPlayer.Playback.compatibilityMode]

        let maxBitrate = try await getMaxBitrate(for: currentVideoBitrate)
        let profile = DeviceProfile.build(
            for: currentVideoPlayerType,
            compatibilityMode: compatibilityMode,
            maxBitrate: maxBitrate
        )

        let userSession = Container.shared.currentUserSession()!

        // For HLS containers, disable direct play to force transcoding
        let enableDirectPlay = mediaSource.container?.lowercased() != "hls"

        let playbackInfo = PlaybackInfoDto(
            deviceProfile: profile,
            enableDirectPlay: enableDirectPlay,
            enableDirectStream: enableDirectPlay
        )
        let playbackInfoParameters = Paths.GetPostedPlaybackInfoParameters(
            userID: userSession.user.id,
            maxStreamingBitrate: maxBitrate,
            mediaSourceID: mediaSource.id
        )

        let request = Paths.getPostedPlaybackInfo(
            itemID: self.id!,
            parameters: playbackInfoParameters,
            playbackInfo
        )

        let response = try await userSession.client.send(request)

        let logger = Logger.swiftfin()
        logger.info("PlaybackInfo response received")
        logger.debug("Media sources count: \(response.value.mediaSources?.count ?? 0)")

        if let mediaSources = response.value.mediaSources {
            for (index, ms) in mediaSources.enumerated() {
                logger
                    .debug(
                        "MediaSource \(index): ID=\(ms.id ?? "nil"), Container=\(ms.container ?? "nil"), TranscodingURL=\(ms.transcodingURL != nil ? "present" : "nil")"
                    )
            }
        }

        guard let matchingMediaSource = response.value.mediaSources?
            .first(where: { $0.eTag == mediaSource.eTag && $0.id == mediaSource.id })
        else {
            throw JellyfinAPIError("Matching media source not in playback info")
        }

        logger.info("Found matching media source with transcoding URL: \(matchingMediaSource.transcodingURL != nil)")

        return try matchingMediaSource.videoPlayerViewModel(with: self, playSessionID: response.value.playSessionID!)
    }

    func liveVideoPlayerViewModel(with mediaSource: MediaSourceInfo, logger: Logger) async throws -> VideoPlayerViewModel {

        let currentVideoPlayerType = Defaults[.VideoPlayer.videoPlayerType]
        let currentVideoBitrate = Defaults[.VideoPlayer.Playback.appMaximumBitrate]
        let compatibilityMode = Defaults[.VideoPlayer.Playback.compatibilityMode]

        let maxBitrate = try await getMaxBitrate(for: currentVideoBitrate)
        let profile = DeviceProfile.build(
            for: currentVideoPlayerType,
            compatibilityMode: compatibilityMode,
            maxBitrate: maxBitrate
        )

        let userSession = Container.shared.currentUserSession()!

        let playbackInfo = PlaybackInfoDto(deviceProfile: profile)
        let playbackInfoParameters = Paths.GetPostedPlaybackInfoParameters(
            userID: userSession.user.id,
            maxStreamingBitrate: maxBitrate
        )

        let request = Paths.getPostedPlaybackInfo(
            itemID: self.id!,
            parameters: playbackInfoParameters,
            playbackInfo
        )

        let response = try await userSession.client.send(request)
        logger.debug("liveVideoPlayerViewModel response received")

        var matchingMediaSource: MediaSourceInfo?
        if let responseMediaSources = response.value.mediaSources {
            for responseMediaSource in responseMediaSources {
                if let openToken = responseMediaSource.openToken, let mediaSourceId = mediaSource.id {
                    if openToken.contains(mediaSourceId) {
                        logger.debug("liveVideoPlayerViewModel found mediaSource with through openToken mediaSourceId match")
                        matchingMediaSource = responseMediaSource
                    }
                }
            }
            if matchingMediaSource == nil && !responseMediaSources.isEmpty {
                // Didn't find a match, but maybe we can just grab the first item in the response
                matchingMediaSource = responseMediaSources.first
                logger.debug("liveVideoPlayerViewModel resorting to first media source in the response")
            }
        }
        guard let matchingMediaSource else {
            logger.debug("liveVideoPlayerViewModel no matchingMediaSource found, throwing error")
            throw JellyfinAPIError("Matching media source not in playback info")
        }

        logger.debug("liveVideoPlayerViewModel matchingMediaSource being returned")
        return try matchingMediaSource.liveVideoPlayerViewModel(
            with: self,
            playSessionID: response.value.playSessionID!
        )
    }

    private func getMaxBitrate(for bitrate: PlaybackBitrate) async throws -> Int {
        let settingBitrate = Defaults[.VideoPlayer.Playback.appMaximumBitrateTest]

        guard bitrate != .auto else {
            return try await testBitrate(with: settingBitrate.rawValue)
        }
        return bitrate.rawValue
    }

    private func testBitrate(with testSize: Int) async throws -> Int {
        precondition(testSize > 0, "testSize must be greater than zero")

        let userSession = Container.shared.currentUserSession()!

        let testStartTime = Date()
        _ = try await userSession.client.send(Paths.getBitrateTestBytes(size: testSize))
        let testDuration = Date().timeIntervalSince(testStartTime)
        let testSizeBits = Double(testSize * 8)
        let testBitrate = testSizeBits / testDuration

        /// Exceeding 500 mbps will produce an invalid URL
        return min(Int(testBitrate), PlaybackBitrate.max.rawValue)
    }
}
