//
//  ContentView.swift
//  Zipka
//
//  Created by Jakub Majka on 4/12/25.
//

import SwiftUI
import MapKit

struct ContentView: View {
    

    var body: some View {
        MapView()
        .edgesIgnoringSafeArea(.all)
    }
}

#Preview {
    ContentView()
}
//
//MapAnnotation(coordinate: vehicle.position) {
//    Circle()
//        .fill(Color.blue)
//        .frame(width: 10, height: 10)
//        .shadow(radius: 2)
//}
