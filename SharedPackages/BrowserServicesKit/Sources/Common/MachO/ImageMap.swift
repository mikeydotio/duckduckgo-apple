//
//  ImageMap.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import MachO

/// Pointer collection used to iterate through Mach-O symbols and rewrite their pointers.
public struct ImageMap {

    let header: UnsafePointer<mach_header_64>

    let symtabCmd: symtab_command?
    let dysymtabCmd: dysymtab_command?
    let chainedFixupsCmd: linkedit_data_command?

    let dataSegment: UnsafePointer<segment_command_64>?
    let dataConstSegment: UnsafePointer<segment_command_64>?
    let segments: [UnsafePointer<segment_command_64>]

    let symtab: UnsafeBufferPointer<nlist_64>?
    let strtab: UnsafeBufferPointer<Int8>?
    // indirect symbol table (array of uint32_t indices into symbol table)
    let indirectSymtab: UnsafeBufferPointer<UInt32>?
    let linkeditBase: UnsafeRawPointer

    public init?(header: UnsafePointer<mach_header_64>, slide: Int) {
        guard case let (symtabCmd, dysymtabCmd, chainedFixupsCmd, linkeditSegment?, dataSegment, dataConstSegment, segments) = Self.findCommandsAndSegments(in: header) else { return nil }
        self.header = header
        self.symtabCmd = symtabCmd
        self.dysymtabCmd = dysymtabCmd
        self.chainedFixupsCmd = chainedFixupsCmd
        self.dataSegment = dataSegment
        self.dataConstSegment = dataConstSegment
        self.segments = segments

        let linkeditBase = UnsafeRawPointer(bitPattern: UInt(linkeditSegment.vmaddr))!.advanced(by: slide - Int(linkeditSegment.fileoff))
        self.linkeditBase = linkeditBase
        self.symtab = symtabCmd.map {
            UnsafeBufferPointer(start: linkeditBase.advanced(by: Int($0.symoff)).assumingMemoryBound(to: nlist_64.self),
                                count: Int($0.nsyms))
        }
        self.strtab = symtabCmd.map {
            UnsafeBufferPointer(start: linkeditBase.advanced(by: Int($0.stroff)).assumingMemoryBound(to: Int8.self),
                                count: Int($0.strsize))
        }
        self.indirectSymtab = dysymtabCmd.map {
            UnsafeBufferPointer(start: linkeditBase.advanced(by: Int($0.indirectsymoff)).assumingMemoryBound(to: UInt32.self),
                                count: Int($0.nindirectsyms))
        }
    }

    private typealias CommandsAndSegments = (symtabCmd: symtab_command?, dysymtabCmd: dysymtab_command?, chainedFixupsCmd: linkedit_data_command?, linkeditSegment: segment_command_64?, dataSegment: UnsafePointer<segment_command_64>?, dataConstSegment: UnsafePointer<segment_command_64>?, segments: [UnsafePointer<segment_command_64>]) // swiftlint:disable:this large_tuple

    /// Find Mach-O loader commands and segments needed for symbol lookup.
    private static func findCommandsAndSegments(in header: UnsafePointer<mach_header_64>) -> CommandsAndSegments {
        var result: CommandsAndSegments = (nil, nil, nil, nil, nil, nil, [])

        for loadCommand in header.loadCommands {
            switch loadCommand.cmd {
            case LC_SYMTAB where result.symtabCmd == nil:
                result.symtabCmd = loadCommand.as(symtab_command.self).pointee
            case LC_DYSYMTAB where result.dysymtabCmd == nil:
                result.dysymtabCmd = loadCommand.as(dysymtab_command.self).pointee
            case Int32(bitPattern: LC_DYLD_CHAINED_FIXUPS) where result.chainedFixupsCmd == nil:
                result.chainedFixupsCmd = loadCommand.as(linkedit_data_command.self)?.pointee
            default:
                guard let segment = loadCommand.as(segment_command_64.self) else { continue }
                result.segments.append(segment)
                switch segment.segname {
                case SEG_LINKEDIT:
                    result.linkeditSegment = segment.pointee
                case SEG_DATA:
                    result.dataSegment = segment
                case "__DATA_CONST":
                    result.dataConstSegment = segment
                default: continue
                }
            }

        }

        return result
    }

    /// Lookup for a symbol name by `symtab` index.
    /// - Returns: C String pointer to the symbol name or `nil` if the provided symbol index is out of bounds or if the symbol `strtab` offset is out of the `strtab` bounds.
    /// - Note: The method returns a pointer to avoid string copying involving `0` terminator character lookup, which may cause out-of-bounds exceptions and has previously caused some crashes.
    /// - Note: `strcmp` should be used for bytewise string comparison.
    func symbolName(at symtabIndex: Int) -> UnsafePointer<CChar>? {
        guard let symtab, let strtab else { return nil }
        guard symtab.indices.contains(symtabIndex) else { return nil }
        let strtabOffset = Int(symtab[symtabIndex].n_un.n_strx)
        guard strtab.indices.contains(strtabOffset),
              strtab.indices.contains(strtabOffset + 1) else { return nil }
        let symbolName = strtab.baseAddress!.advanced(by: Int(strtabOffset))
        return symbolName
    }

}
