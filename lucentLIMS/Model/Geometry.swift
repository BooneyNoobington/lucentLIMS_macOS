import Foundation

/// Plane geometry on latitude and longitude, good enough for sites of a few kilometres.

extension Site {
    /// Whether a point lies inside the border (ray casting).
    func contains(_ point: GeoPoint) -> Bool {
        guard border.count >= 3 else { return false }
        var inside = false
        var j = border.count - 1
        for i in border.indices {
            let a = border[i], b = border[j]
            if (a.latitude > point.latitude) != (b.latitude > point.latitude),
               point.longitude < (b.longitude - a.longitude) * (point.latitude - a.latitude)
                / (b.latitude - a.latitude) + a.longitude {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
}

enum Border {
    /// Whether the closed ring through `points` crosses or touches itself, as lucentAPI checks it.
    static func crossesItself(_ points: [GeoPoint]) -> Bool {
        guard points.count >= 4 else { return false }
        let ring = points + [points[0]]
        let edges = Array(zip(ring, ring.dropFirst()))
        for i in edges.indices {
            for j in edges.indices where j > i + 1 && !(i == 0 && j == edges.count - 1) {
                if meet(edges[i].0, edges[i].1, edges[j].0, edges[j].1) { return true }
            }
        }
        return false
    }

    /// At least three different corners.
    static func isLargeEnough(_ points: [GeoPoint]) -> Bool {
        Set(points).count >= 3
    }

    private static func orientation(_ p: GeoPoint, _ q: GeoPoint, _ r: GeoPoint) -> Int {
        let value = (q.latitude - p.latitude) * (r.longitude - q.longitude)
            - (q.longitude - p.longitude) * (r.latitude - q.latitude)
        return value == 0 ? 0 : value > 0 ? 1 : -1
    }

    /// Whether q, collinear with p and r, lies between them.
    private static func between(_ p: GeoPoint, _ q: GeoPoint, _ r: GeoPoint) -> Bool {
        (min(p.longitude, r.longitude)...max(p.longitude, r.longitude)).contains(q.longitude)
            && (min(p.latitude, r.latitude)...max(p.latitude, r.latitude)).contains(q.latitude)
    }

    private static func meet(_ a: GeoPoint, _ b: GeoPoint, _ c: GeoPoint, _ d: GeoPoint) -> Bool {
        let o1 = orientation(a, b, c), o2 = orientation(a, b, d), o3 = orientation(c, d, a), o4 = orientation(c, d, b)
        if o1 != o2 && o3 != o4 { return true }
        return (o1 == 0 && between(a, c, b)) || (o2 == 0 && between(a, d, b))
            || (o3 == 0 && between(c, a, d)) || (o4 == 0 && between(c, b, d))
    }
}
