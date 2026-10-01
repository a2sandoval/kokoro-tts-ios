import Foundation

/// A Kokoro voice. `sid` is the speaker id passed to the engine.
/// The order below is the exact `speaker_names` order from the
/// `csukuangfj/kokoro-int8-multi-lang-v1_0` model metadata (Kokoro v1.0, 54 voices).
struct KokoroVoice: Identifiable, Hashable {
    let sid: Int
    let code: String  // e.g. "af_heart"

    var id: Int { sid }

    var accentDescription: String {
        switch code.prefix(2) {
        case "af": return "American Female"
        case "am": return "American Male"
        case "bf": return "British Female"
        case "bm": return "British Male"
        case "ef": return "Spanish Female"
        case "em": return "Spanish Male"
        case "ff": return "French Female"
        case "hf": return "Hindi Female"
        case "hm": return "Hindi Male"
        case "if": return "Italian Female"
        case "im": return "Italian Male"
        case "jf": return "Japanese Female"
        case "jm": return "Japanese Male"
        case "pf": return "Portuguese Female"
        case "pm": return "Portuguese Male"
        case "zf": return "Chinese Female"
        case "zm": return "Chinese Male"
        default: return "Voice"
        }
    }

    var displayName: String {
        code.split(separator: "_").dropFirst().joined(separator: " ").capitalized
    }

    var isEnglish: Bool {
        let p = code.prefix(2)
        return p == "af" || p == "am" || p == "bf" || p == "bm"
    }

    static let all: [KokoroVoice] = [
        KokoroVoice(sid: 0, code: "af_alloy"),
        KokoroVoice(sid: 1, code: "af_aoede"),
        KokoroVoice(sid: 2, code: "af_bella"),
        KokoroVoice(sid: 3, code: "af_heart"),
        KokoroVoice(sid: 4, code: "af_jessica"),
        KokoroVoice(sid: 5, code: "af_kore"),
        KokoroVoice(sid: 6, code: "af_nicole"),
        KokoroVoice(sid: 7, code: "af_nova"),
        KokoroVoice(sid: 8, code: "af_river"),
        KokoroVoice(sid: 9, code: "af_sarah"),
        KokoroVoice(sid: 10, code: "af_sky"),
        KokoroVoice(sid: 11, code: "am_adam"),
        KokoroVoice(sid: 12, code: "am_echo"),
        KokoroVoice(sid: 13, code: "am_eric"),
        KokoroVoice(sid: 14, code: "am_fenrir"),
        KokoroVoice(sid: 15, code: "am_liam"),
        KokoroVoice(sid: 16, code: "am_michael"),
        KokoroVoice(sid: 17, code: "am_onyx"),
        KokoroVoice(sid: 18, code: "am_puck"),
        KokoroVoice(sid: 19, code: "am_santa"),
        KokoroVoice(sid: 20, code: "bf_alice"),
        KokoroVoice(sid: 21, code: "bf_emma"),
        KokoroVoice(sid: 22, code: "bf_isabella"),
        KokoroVoice(sid: 23, code: "bf_lily"),
        KokoroVoice(sid: 24, code: "bm_daniel"),
        KokoroVoice(sid: 25, code: "bm_fable"),
        KokoroVoice(sid: 26, code: "bm_george"),
        KokoroVoice(sid: 27, code: "bm_lewis"),
        KokoroVoice(sid: 28, code: "ef_dora"),
        KokoroVoice(sid: 29, code: "em_alex"),
        KokoroVoice(sid: 30, code: "ff_siwis"),
        KokoroVoice(sid: 31, code: "hf_alpha"),
        KokoroVoice(sid: 32, code: "hf_beta"),
        KokoroVoice(sid: 33, code: "hm_omega"),
        KokoroVoice(sid: 34, code: "hm_psi"),
        KokoroVoice(sid: 35, code: "if_sara"),
        KokoroVoice(sid: 36, code: "im_nicola"),
        KokoroVoice(sid: 37, code: "jf_alpha"),
        KokoroVoice(sid: 38, code: "jf_gongitsune"),
        KokoroVoice(sid: 39, code: "jf_nezumi"),
        KokoroVoice(sid: 40, code: "jf_tebukuro"),
        KokoroVoice(sid: 41, code: "jm_kumo"),
        KokoroVoice(sid: 42, code: "pf_dora"),
        KokoroVoice(sid: 43, code: "pm_alex"),
        KokoroVoice(sid: 44, code: "pm_santa"),
        KokoroVoice(sid: 45, code: "zf_xiaobei"),
        KokoroVoice(sid: 46, code: "zf_xiaoni"),
        KokoroVoice(sid: 47, code: "zf_xiaoxiao"),
        KokoroVoice(sid: 48, code: "zf_xiaoyi"),
        KokoroVoice(sid: 49, code: "zm_yunjian"),
        KokoroVoice(sid: 50, code: "zm_yunxi"),
        KokoroVoice(sid: 51, code: "zm_yunxia"),
        KokoroVoice(sid: 52, code: "zm_yunyang"),
        KokoroVoice(sid: 53, code: "em_santa"),
    ]

    static let english = all.filter(\.isEnglish)
    static let other = all.filter { !$0.isEnglish }

    /// af_heart — the most popular Kokoro English voice.
    static let `default` = all[3]
}
