//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2025 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import OrderedCollections
import SwiftUI

extension ItemView {

    struct PersonItemContentView: View {

        typealias Element = OrderedDictionary<BaseItemKind, ItemLibraryViewModel>.Elements.Element

        @ObservedObject
        var viewModel: PersonItemViewModel

        @Router
        private var router

        var body: some View {
            VStack(spacing: 0) {

                ItemView.CinematicHeaderView(viewModel: viewModel)
                    .padding(.bottom, 50)

                // MARK: - Items by Type

                ForEach(viewModel.sections.elements, id: \.key) { element in
                    if element.value.elements.isNotEmpty {
                        PosterHStack(
                            title: element.key.pluralDisplayTitle,
                            type: .portrait,
                            items: element.value.elements
                        ) { item in
                            router.route(to: .item(item: item))
                        }
                    }
                }

                ItemView.AboutView(viewModel: viewModel)
            }
        }
    }
}
