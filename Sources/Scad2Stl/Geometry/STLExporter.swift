import Foundation
import Euclid

public struct STLExporter {
    public enum Format {
        case binary
        case ascii
    }
    
    public static func export(mesh: Mesh, format: Format = .binary, name: String = "Scad2Stl_Model") -> Data {
        switch format {
        case .binary:
            var header = "Scad2Stl Exported Binary STL - Model: \(name)".data(using: .utf8) ?? Data()
            if header.count < 80 {
                header.append(Data(count: 80 - header.count))
            } else if header.count > 80 {
                header = header.prefix(80)
            }
            let options = STLBinaryOptions(header: header)
            return mesh.stlData(options: options)
            
        case .ascii:
            let str = mesh.stlString(name: name)
            return str.data(using: .utf8) ?? Data()
        }
    }
    
    public static func exportToFile(mesh: Mesh, at url: URL, format: Format = .binary, name: String = "Model") throws {
        let data = export(mesh: mesh, format: format, name: name)
        try data.write(to: url, options: .atomic)
    }
}
