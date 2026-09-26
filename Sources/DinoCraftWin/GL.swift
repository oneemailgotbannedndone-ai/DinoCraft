import Foundation
import CSDL3
import DinoCraftCore

/// OpenGL 3.3 core constants used by the Windows renderer.
enum GLC {
    static let COLOR_BUFFER_BIT: UInt32 = 0x4000
    static let DEPTH_BUFFER_BIT: UInt32 = 0x0100
    static let DEPTH_TEST: UInt32 = 0x0B71
    static let CULL_FACE: UInt32 = 0x0B44
    static let BACK: UInt32 = 0x0405
    static let CCW: UInt32 = 0x0901
    /// GL_NVX_gpu_memory_info: dedicated video memory and what's currently free, in KB.
    static let GPU_MEMORY_DEDICATED_NVX: UInt32 = 0x9047
    static let GPU_MEMORY_AVAILABLE_NVX: UInt32 = 0x9049
    static let NUM_EXTENSIONS: UInt32 = 0x821D
    static let EXTENSIONS: UInt32 = 0x1F03
    static let BLEND: UInt32 = 0x0BE2
    static let LESS: UInt32 = 0x0201
    static let ONE: UInt32 = 1
    static let ONE_MINUS_SRC_ALPHA: UInt32 = 0x0303
    static let TRIANGLES: UInt32 = 0x0004
    static let UNSIGNED_BYTE: UInt32 = 0x1401
    static let UNSIGNED_SHORT: UInt32 = 0x1403
    static let UNSIGNED_INT: UInt32 = 0x1405
    static let FLOAT: UInt32 = 0x1406
    static let ARRAY_BUFFER: UInt32 = 0x8892
    static let ELEMENT_ARRAY_BUFFER: UInt32 = 0x8893
    static let STATIC_DRAW: UInt32 = 0x88E4
    static let DYNAMIC_DRAW: UInt32 = 0x88E8
    static let VERTEX_SHADER: UInt32 = 0x8B31
    static let FRAGMENT_SHADER: UInt32 = 0x8B30
    static let COMPILE_STATUS: UInt32 = 0x8B81
    static let LINK_STATUS: UInt32 = 0x8B82
    static let INFO_LOG_LENGTH: UInt32 = 0x8B84
    static let TEXTURE_2D_ARRAY: UInt32 = 0x8C1A
    static let TEXTURE0: UInt32 = 0x84C0
    static let TEXTURE_MIN_FILTER: UInt32 = 0x2801
    static let TEXTURE_MAG_FILTER: UInt32 = 0x2800
    static let TEXTURE_WRAP_S: UInt32 = 0x2802
    static let TEXTURE_WRAP_T: UInt32 = 0x2803
    static let REPEAT: Int32 = 0x2901
    static let NEAREST: Int32 = 0x2600
    static let NEAREST_MIPMAP_LINEAR: Int32 = 0x2702
    static let SRGB8_ALPHA8: Int32 = 0x8C43
    static let RGBA: UInt32 = 0x1908
    static let FRAMEBUFFER_SRGB: UInt32 = 0x8DB9
    static let PACK_ALIGNMENT: UInt32 = 0x0D05
    static let UNPACK_ALIGNMENT: UInt32 = 0x0CF5
    static let VENDOR: UInt32 = 0x1F00
    static let RENDERER: UInt32 = 0x1F01
    static let VERSION: UInt32 = 0x1F02
    static let TEXTURE_2D: UInt32 = 0x0DE1
    static let LINEAR: Int32 = 0x2601
    static let CLAMP_TO_EDGE: Int32 = 0x812F
    static let RGBA16F: Int32 = 0x881A
    static let FRAMEBUFFER: UInt32 = 0x8D40
    static let RENDERBUFFER: UInt32 = 0x8D41
    static let COLOR_ATTACHMENT0: UInt32 = 0x8CE0
    static let DEPTH_ATTACHMENT: UInt32 = 0x8D00
    static let DEPTH_COMPONENT24: UInt32 = 0x81A6
    static let FRAMEBUFFER_COMPLETE: UInt32 = 0x8CD5
}

enum GLError: Error, CustomStringConvertible {
    case missingFunction(String)
    case shader(String)

    var description: String {
        switch self {
        case .missingFunction(let name): return "Your graphics driver is missing the OpenGL function \(name). DinoCraft needs OpenGL 3.3."
        case .shader(let log): return "A DinoCraft shader failed to build:\n\(log)"
        }
    }
}

/// OpenGL entry points loaded at runtime through SDL, so no GL loader library is needed.
final class GL {
    let viewport: @convention(c) (Int32, Int32, Int32, Int32) -> Void
    let clearColor: @convention(c) (Float, Float, Float, Float) -> Void
    let clear: @convention(c) (UInt32) -> Void
    let enable: @convention(c) (UInt32) -> Void
    let disable: @convention(c) (UInt32) -> Void
    let depthFunc: @convention(c) (UInt32) -> Void
    let depthMask: @convention(c) (UInt8) -> Void
    let blendFunc: @convention(c) (UInt32, UInt32) -> Void
    let genVertexArrays: @convention(c) (Int32, UnsafeMutablePointer<UInt32>?) -> Void
    let bindVertexArray: @convention(c) (UInt32) -> Void
    let deleteVertexArrays: @convention(c) (Int32, UnsafePointer<UInt32>?) -> Void
    let genBuffers: @convention(c) (Int32, UnsafeMutablePointer<UInt32>?) -> Void
    let bindBuffer: @convention(c) (UInt32, UInt32) -> Void
    let bufferData: @convention(c) (UInt32, Int, UnsafeRawPointer?, UInt32) -> Void
    let deleteBuffers: @convention(c) (Int32, UnsafePointer<UInt32>?) -> Void
    let vertexAttribPointer: @convention(c) (UInt32, Int32, UInt32, UInt8, Int32, UnsafeRawPointer?) -> Void
    let vertexAttribIPointer: @convention(c) (UInt32, Int32, UInt32, Int32, UnsafeRawPointer?) -> Void
    let enableVertexAttribArray: @convention(c) (UInt32) -> Void
    let createShader: @convention(c) (UInt32) -> UInt32
    let shaderSource: @convention(c) (UInt32, Int32, UnsafePointer<UnsafePointer<CChar>?>?, UnsafePointer<Int32>?) -> Void
    let compileShader: @convention(c) (UInt32) -> Void
    let getShaderiv: @convention(c) (UInt32, UInt32, UnsafeMutablePointer<Int32>?) -> Void
    let getShaderInfoLog: @convention(c) (UInt32, Int32, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<CChar>?) -> Void
    let deleteShader: @convention(c) (UInt32) -> Void
    let createProgram: @convention(c) () -> UInt32
    let attachShader: @convention(c) (UInt32, UInt32) -> Void
    let linkProgram: @convention(c) (UInt32) -> Void
    let getProgramiv: @convention(c) (UInt32, UInt32, UnsafeMutablePointer<Int32>?) -> Void
    let getProgramInfoLog: @convention(c) (UInt32, Int32, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<CChar>?) -> Void
    let useProgram: @convention(c) (UInt32) -> Void
    let getUniformLocation: @convention(c) (UInt32, UnsafePointer<CChar>?) -> Int32
    let uniformMatrix4fv: @convention(c) (Int32, Int32, UInt8, UnsafePointer<Float>?) -> Void
    let uniform4f: @convention(c) (Int32, Float, Float, Float, Float) -> Void
    let uniform3f: @convention(c) (Int32, Float, Float, Float) -> Void
    let uniform2f: @convention(c) (Int32, Float, Float) -> Void
    let uniform1f: @convention(c) (Int32, Float) -> Void
    let uniform1i: @convention(c) (Int32, Int32) -> Void
    let genTextures: @convention(c) (Int32, UnsafeMutablePointer<UInt32>?) -> Void
    let deleteTextures: @convention(c) (Int32, UnsafeMutablePointer<UInt32>?) -> Void
    let bindTexture: @convention(c) (UInt32, UInt32) -> Void
    let activeTexture: @convention(c) (UInt32) -> Void
    let texImage3D: @convention(c) (UInt32, Int32, Int32, Int32, Int32, Int32, Int32, UInt32, UInt32, UnsafeRawPointer?) -> Void
    let texParameteri: @convention(c) (UInt32, UInt32, Int32) -> Void
    let generateMipmap: @convention(c) (UInt32) -> Void
    let drawElementsBaseVertex: @convention(c) (UInt32, Int32, UInt32, UnsafeRawPointer?, Int32) -> Void
    let drawArrays: @convention(c) (UInt32, Int32, Int32) -> Void
    let readPixels: @convention(c) (Int32, Int32, Int32, Int32, UInt32, UInt32, UnsafeMutableRawPointer?) -> Void
    let pixelStorei: @convention(c) (UInt32, Int32) -> Void
    let getString: @convention(c) (UInt32) -> UnsafePointer<UInt8>?
    let getStringi: @convention(c) (UInt32, UInt32) -> UnsafePointer<UInt8>?
    let getIntegerv: @convention(c) (UInt32, UnsafeMutablePointer<Int32>?) -> Void
    let cullFace: @convention(c) (UInt32) -> Void
    let frontFace: @convention(c) (UInt32) -> Void
    let getError: @convention(c) () -> UInt32
    let texImage2D: @convention(c) (UInt32, Int32, Int32, Int32, Int32, Int32, UInt32, UInt32, UnsafeRawPointer?) -> Void
    let genFramebuffers: @convention(c) (Int32, UnsafeMutablePointer<UInt32>?) -> Void
    let deleteFramebuffers: @convention(c) (Int32, UnsafeMutablePointer<UInt32>?) -> Void
    let bindFramebuffer: @convention(c) (UInt32, UInt32) -> Void
    let framebufferTexture2D: @convention(c) (UInt32, UInt32, UInt32, UInt32, Int32) -> Void
    let checkFramebufferStatus: @convention(c) (UInt32) -> UInt32
    let genRenderbuffers: @convention(c) (Int32, UnsafeMutablePointer<UInt32>?) -> Void
    let deleteRenderbuffers: @convention(c) (Int32, UnsafeMutablePointer<UInt32>?) -> Void
    let bindRenderbuffer: @convention(c) (UInt32, UInt32) -> Void
    let renderbufferStorage: @convention(c) (UInt32, UInt32, Int32, Int32) -> Void
    let framebufferRenderbuffer: @convention(c) (UInt32, UInt32, UInt32, UInt32) -> Void

    /// Requires a current OpenGL context.
    init() throws {
        func load<T>(_ name: String) throws -> T {
            guard let fn = SDL_GL_GetProcAddress(name) else { throw GLError.missingFunction(name) }
            return unsafeBitCast(fn, to: T.self)
        }
        viewport = try load("glViewport")
        clearColor = try load("glClearColor")
        clear = try load("glClear")
        enable = try load("glEnable")
        disable = try load("glDisable")
        depthFunc = try load("glDepthFunc")
        depthMask = try load("glDepthMask")
        blendFunc = try load("glBlendFunc")
        genVertexArrays = try load("glGenVertexArrays")
        bindVertexArray = try load("glBindVertexArray")
        deleteVertexArrays = try load("glDeleteVertexArrays")
        genBuffers = try load("glGenBuffers")
        bindBuffer = try load("glBindBuffer")
        bufferData = try load("glBufferData")
        deleteBuffers = try load("glDeleteBuffers")
        vertexAttribPointer = try load("glVertexAttribPointer")
        vertexAttribIPointer = try load("glVertexAttribIPointer")
        enableVertexAttribArray = try load("glEnableVertexAttribArray")
        createShader = try load("glCreateShader")
        shaderSource = try load("glShaderSource")
        compileShader = try load("glCompileShader")
        getShaderiv = try load("glGetShaderiv")
        getShaderInfoLog = try load("glGetShaderInfoLog")
        deleteShader = try load("glDeleteShader")
        createProgram = try load("glCreateProgram")
        attachShader = try load("glAttachShader")
        linkProgram = try load("glLinkProgram")
        getProgramiv = try load("glGetProgramiv")
        getProgramInfoLog = try load("glGetProgramInfoLog")
        useProgram = try load("glUseProgram")
        getUniformLocation = try load("glGetUniformLocation")
        uniformMatrix4fv = try load("glUniformMatrix4fv")
        uniform4f = try load("glUniform4f")
        uniform3f = try load("glUniform3f")
        uniform2f = try load("glUniform2f")
        uniform1f = try load("glUniform1f")
        uniform1i = try load("glUniform1i")
        genTextures = try load("glGenTextures")
        deleteTextures = try load("glDeleteTextures")
        bindTexture = try load("glBindTexture")
        activeTexture = try load("glActiveTexture")
        texImage3D = try load("glTexImage3D")
        texParameteri = try load("glTexParameteri")
        generateMipmap = try load("glGenerateMipmap")
        drawElementsBaseVertex = try load("glDrawElementsBaseVertex")
        drawArrays = try load("glDrawArrays")
        readPixels = try load("glReadPixels")
        pixelStorei = try load("glPixelStorei")
        getString = try load("glGetString")
        getStringi = try load("glGetStringi")
        getIntegerv = try load("glGetIntegerv")
        cullFace = try load("glCullFace")
        frontFace = try load("glFrontFace")
        getError = try load("glGetError")
        texImage2D = try load("glTexImage2D")
        genFramebuffers = try load("glGenFramebuffers")
        deleteFramebuffers = try load("glDeleteFramebuffers")
        bindFramebuffer = try load("glBindFramebuffer")
        framebufferTexture2D = try load("glFramebufferTexture2D")
        checkFramebufferStatus = try load("glCheckFramebufferStatus")
        genRenderbuffers = try load("glGenRenderbuffers")
        deleteRenderbuffers = try load("glDeleteRenderbuffers")
        bindRenderbuffer = try load("glBindRenderbuffer")
        renderbufferStorage = try load("glRenderbufferStorage")
        framebufferRenderbuffer = try load("glFramebufferRenderbuffer")
    }

    // MARK: Helpers

    func string(_ name: UInt32) -> String {
        guard let p = getString(name) else { return "?" }
        return String(cString: p)
    }

    func hasExtension(_ name: String) -> Bool {
        var count: Int32 = 0
        getIntegerv(GLC.NUM_EXTENSIONS, &count)
        for i in 0..<max(0, count) {
            if let p = getStringi(GLC.EXTENSIONS, UInt32(i)), String(cString: p) == name { return true }
        }
        return false
    }

    /// Dedicated video memory and what's free, in MB, from NVIDIA drivers (nil elsewhere).
    func videoMemoryMB() -> (total: Int, free: Int)? {
        if hasExtension("GL_NVX_gpu_memory_info") {
            var total: Int32 = 0, free: Int32 = 0
            getIntegerv(GLC.GPU_MEMORY_DEDICATED_NVX, &total)
            getIntegerv(GLC.GPU_MEMORY_AVAILABLE_NVX, &free)
            // Only believe values a real graphics card could have (software renderers report nonsense here).
            if total > 0 && total / 1024 <= 65536 && free >= 0 && free <= total { return (Int(total) / 1024, Int(free) / 1024) }
        }
        return nil
    }

    func makeBuffer() -> UInt32 {
        var id: UInt32 = 0
        genBuffers(1, &id)
        return id
    }

    func makeVertexArray() -> UInt32 {
        var id: UInt32 = 0
        genVertexArrays(1, &id)
        return id
    }

    func makeTexture() -> UInt32 {
        var id: UInt32 = 0
        genTextures(1, &id)
        return id
    }

    func deleteTexture(_ id: UInt32) {
        var copy = id
        deleteTextures(1, &copy)
    }

    func deleteBuffer(_ id: UInt32) {
        var copy = id
        deleteBuffers(1, &copy)
    }

    func deleteVertexArray(_ id: UInt32) {
        var copy = id
        deleteVertexArrays(1, &copy)
    }

    func uniform(_ program: UInt32, _ name: String) -> Int32 { getUniformLocation(program, name) }

    func setMatrix(_ location: Int32, _ m: Mat4) {
        var values: [Float] = [
            m.columns.0.x, m.columns.0.y, m.columns.0.z, m.columns.0.w,
            m.columns.1.x, m.columns.1.y, m.columns.1.z, m.columns.1.w,
            m.columns.2.x, m.columns.2.y, m.columns.2.z, m.columns.2.w,
            m.columns.3.x, m.columns.3.y, m.columns.3.z, m.columns.3.w,
        ]
        uniformMatrix4fv(location, 1, 0, &values)
    }

    private func compile(_ type: UInt32, _ source: String, label: String) throws -> UInt32 {
        let shader = createShader(type)
        source.withCString { cString in
            var pointer: UnsafePointer<CChar>? = cString
            withUnsafePointer(to: &pointer) { shaderSource(shader, 1, $0, nil) }
        }
        compileShader(shader)
        var ok: Int32 = 0
        getShaderiv(shader, GLC.COMPILE_STATUS, &ok)
        if ok == 0 {
            throw GLError.shader("\(label): \(infoLog(shader, program: false))")
        }
        return shader
    }

    private func infoLog(_ id: UInt32, program: Bool) -> String {
        var length: Int32 = 0
        if program { getProgramiv(id, GLC.INFO_LOG_LENGTH, &length) } else { getShaderiv(id, GLC.INFO_LOG_LENGTH, &length) }
        guard length > 1 else { return "(no log)" }
        var buffer = [CChar](repeating: 0, count: Int(length) + 1)
        if program { getProgramInfoLog(id, length, nil, &buffer) } else { getShaderInfoLog(id, length, nil, &buffer) }
        return String(cString: buffer)
    }

    func makeProgram(vertex: String, fragment: String, label: String) throws -> UInt32 {
        let vs = try compile(GLC.VERTEX_SHADER, vertex, label: "\(label) vertex")
        let fs = try compile(GLC.FRAGMENT_SHADER, fragment, label: "\(label) fragment")
        let program = createProgram()
        attachShader(program, vs)
        attachShader(program, fs)
        linkProgram(program)
        var ok: Int32 = 0
        getProgramiv(program, GLC.LINK_STATUS, &ok)
        if ok == 0 { throw GLError.shader("\(label) link: \(infoLog(program, program: true))") }
        deleteShader(vs)
        deleteShader(fs)
        return program
    }
}
