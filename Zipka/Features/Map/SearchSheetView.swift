//
//  SearchSheetView.swift
//  Zipka
//
//  Created by Jakub Majka on 9/1/26.
//

import SwiftUI

struct SearchSheetView: View {
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Search Stop or Line", text: $searchText).fontWeight(.semibold)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
                .background(Color(.systemGray6))
                .clipShape(Capsule())
                
                Button(action: {
                }) {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .frame(width: 36, height: 36)
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal)
            .padding(.top)
            
            Spacer()
        }
    }
}

#Preview {
    SearchSheetView()
}
