import Foundation

struct VocabWord: Identifiable, Hashable {
    var id: String { en }
    let en: String
    let tr: String
    let example: String
    let level: String
}

struct CuratedLesson: Identifiable {
    let id: String
    let content: LessonContent
}

struct Level: Identifiable {
    var id: String { code }
    let code: String
    let name: String
    let lessons: [CuratedLesson]
}

private func L(_ id: String, _ title: String, _ explanation: String, _ examples: [String],
               _ ex: [(String, String)]) -> CuratedLesson {
    CuratedLesson(id: id, content: LessonContent(
        title: title, explanation: explanation, examples: examples,
        exercises: ex.map { .init(prompt: $0.0, answer: $0.1) }))
}

enum Content {
    static let levels: [Level] = [
        Level(code: "A1", name: "Başlangıç", lessons: [
            L("a1-be", "To be: am / is / are",
              "İngilizce'de 'olmak' fiili özneye göre değişir: I am, he/she/it is, you/we/they are. Türkçe'de bu fiil çoğu zaman görünmez ama İngilizce'de cümlede mutlaka bulunmalıdır. Olumsuz için not eklenir: I am not, he is not (isn't), they are not (aren't).",
              ["I am a student.", "She is my sister.", "They are at home.", "He is not tired."],
              [("She ___ a teacher.", "is"), ("We ___ friends.", "are"), ("I ___ hungry.", "am"), ("It ___ not expensive.", "is")]),
            L("a1-articles", "Articles: a / an / the",
              "'a' ve 'an' belirsiz tekil bir şeyi anlatır; sesli harfle başlayan sözcüklerden önce 'an' kullanılır (an apple, an hour). 'the' ise iki tarafın da bildiği belirli şey için kullanılır. Çoğul ve sayılamayan isimlerle 'a/an' kullanılmaz.",
              ["I have a dog.", "She eats an apple.", "The dog is very big.", "Water is important."],
              [("He is ___ engineer.", "an"), ("I saw ___ good movie yesterday.", "a"), ("___ sun is hot. (the/a)", "The"), ("She has ___ umbrella.", "an")]),
            L("a1-present", "Present Simple",
              "Alışkanlıklar ve genel doğrular için kullanılır. I/you/we/they ile fiilin yalın hali kullanılır; he/she/it ile fiile -s/-es eklenir (she works, he goes). Olumsuz ve soru için do/does gerekir; does ile fiil yalın kalır: Does she work?",
              ["I work every day.", "He plays football on Sundays.", "Do you like coffee?", "She doesn't eat meat."],
              [("She ___ (work) in a bank.", "works"), ("They ___ (not/like) tea.", "don't like"), ("___ he speak English? (do/does)", "Does"), ("My brother ___ (go) to school by bus.", "goes")]),
        ]),
        Level(code: "A2", name: "Temel", lessons: [
            L("a2-past", "Past Simple",
              "Geçmişte bitmiş olaylar için kullanılır. Düzenli fiillere -ed eklenir (work → worked). Düzensiz fiillerin ayrı biçimi vardır (go → went, see → saw). Olumsuz ve soruda did kullanılır ve fiil yalın kalır: I didn't go. Did you go?",
              ["I visited my aunt yesterday.", "She went to Izmir last week.", "Did you see the film?", "We didn't have time."],
              [("Yesterday I ___ (go) to the market.", "went"), ("She ___ (not/call) me.", "didn't call"), ("___ you finish the homework? (did/do)", "Did"), ("They ___ (buy) a new car.", "bought")]),
            L("a2-prep", "Prepositions of time: in / on / at",
              "'at' saat ve belirli anlar için (at 5 o'clock, at night), 'on' günler ve tarihler için (on Monday, on May 5th), 'in' aylar, mevsimler, yıllar ve günün bölümleri için kullanılır (in July, in 2020, in the morning).",
              ["The class starts at 9.", "I see her on Fridays.", "We travel in summer.", "He was born in 1995."],
              [("The meeting is ___ Monday.", "on"), ("I wake up ___ 7 o'clock.", "at"), ("She was born ___ April.", "in"), ("I am busy ___ the moment.", "at")]),
            L("a2-comp", "Comparatives",
              "Kısa sıfatlara -er eklenir ve than ile karşılaştırılır (taller than). Uzun sıfatlarda more kullanılır (more expensive than). Düzensizler: good → better, bad → worse.",
              ["My house is bigger than yours.", "This book is more interesting than that one.", "Today is better than yesterday.", "She is taller than her brother."],
              [("A car is ___ (fast) than a bike.", "faster"), ("This test is ___ (difficult) than the last one.", "more difficult"), ("My English is ___ (good) now.", "better"), ("Winter is ___ (cold) than autumn.", "colder")]),
        ]),
        Level(code: "B1", name: "Orta", lessons: [
            L("b1-perfect", "Present Perfect",
              "have/has + üçüncü fiil biçimi (V3) ile kurulur. Geçmişte olan ama şimdiyle bağlantısı olan durumlar için kullanılır: deneyimler (I have visited Rome), şimdiye kadar süren durumlar (I have lived here for 5 years). Belirli bir geçmiş zaman (yesterday, in 2010) ile birlikte kullanılmaz.",
              ["I have lost my keys.", "She has lived here since 2019.", "Have you ever been to London?", "We haven't finished yet."],
              [("I ___ (see) that film twice.", "have seen"), ("She ___ (live) here for ten years.", "has lived"), ("___ you ever tried sushi? (have/did)", "Have"), ("They ___ (not/arrive) yet.", "haven't arrived")]),
            L("b1-cond", "Conditionals (If clauses)",
              "Type 1: gerçekçi gelecek ihtimali: If + present, will + fiil (If it rains, I will stay home). Type 2: hayali/olası olmayan durum: If + past, would + fiil (If I had money, I would travel). If cümlesinde will/would kullanılmaz.",
              ["If you study, you will pass.", "If I were rich, I would buy a boat.", "If she calls, tell her I'm busy.", "I would help you if I could."],
              [("If it ___ (rain), we will cancel the picnic.", "rains"), ("If I ___ (have) more time, I would learn Spanish.", "had"), ("She ___ (be) happy if you came. (would be)", "would be"), ("If he ___ (study), he will pass.", "studies")]),
            L("b1-modals", "Modal verbs: should, must, might",
              "should: tavsiye (You should rest). must: güçlü zorunluluk ya da kesin çıkarım (You must wear a seatbelt; He must be tired). might: zayıf ihtimal (It might rain). Modal'dan sonra fiil yalın halde gelir, to kullanılmaz ve -s eklenmez.",
              ["You should drink more water.", "You must stop at a red light.", "It might snow tomorrow.", "She can't be at home."],
              [("You ___ see a doctor. (tavsiye)", "should"), ("It ___ rain later. (belki)", "might"), ("Students ___ wear a uniform here. (zorunlu)", "must"), ("He should ___ (go) to bed early.", "go")]),
        ]),
    ]

    static var allLessons: [CuratedLesson] { levels.flatMap(\.lessons) }

    static let vocabulary: [VocabWord] = {
        let raw: [(String, String, String, String)] = [
            // A1
            ("hello", "merhaba", "Hello, how are you?", "A1"), ("thanks", "teşekkürler", "Thanks for your help.", "A1"),
            ("water", "su", "I drink water every day.", "A1"), ("food", "yiyecek", "The food is delicious.", "A1"),
            ("friend", "arkadaş", "He is my best friend.", "A1"), ("house", "ev", "We live in a small house.", "A1"),
            ("family", "aile", "My family is very big.", "A1"), ("school", "okul", "She goes to school by bus.", "A1"),
            ("happy", "mutlu", "I am happy today.", "A1"), ("big", "büyük", "That is a big dog.", "A1"),
            ("small", "küçük", "The room is small.", "A1"), ("eat", "yemek yemek", "We eat dinner at seven.", "A1"),
            ("drink", "içmek", "Do you drink tea?", "A1"), ("go", "gitmek", "I go to work at eight.", "A1"),
            ("come", "gelmek", "Please come here.", "A1"), ("today", "bugün", "Today is Monday.", "A1"),
            ("tomorrow", "yarın", "See you tomorrow.", "A1"), ("morning", "sabah", "I run in the morning.", "A1"),
            ("night", "gece", "Good night!", "A1"), ("book", "kitap", "I read a book every week.", "A1"),
            // A2
            ("travel", "seyahat etmek", "I love to travel.", "A2"), ("weather", "hava durumu", "The weather is nice today.", "A2"),
            ("cheap", "ucuz", "This shirt is cheap.", "A2"), ("expensive", "pahalı", "The hotel was expensive.", "A2"),
            ("ticket", "bilet", "I bought a train ticket.", "A2"), ("hungry", "aç", "I am very hungry.", "A2"),
            ("tired", "yorgun", "She is tired after work.", "A2"), ("early", "erken", "He wakes up early.", "A2"),
            ("late", "geç", "Sorry, I am late.", "A2"), ("usually", "genellikle", "I usually walk to school.", "A2"),
            ("borrow", "ödünç almak", "Can I borrow your pen?", "A2"), ("leave", "ayrılmak, bırakmak", "The bus leaves at nine.", "A2"),
            ("arrive", "varmak", "We arrived at noon.", "A2"), ("decide", "karar vermek", "I can't decide what to eat.", "A2"),
            ("follow", "takip etmek", "Follow me, please.", "A2"), ("lost", "kayıp, kaybolmuş", "I am lost.", "A2"),
            ("crowded", "kalabalık", "The market is crowded.", "A2"), ("neighbor", "komşu", "My neighbor is friendly.", "A2"),
            ("invite", "davet etmek", "She invited me to dinner.", "A2"), ("prepare", "hazırlamak", "I prepared breakfast.", "A2"),
            // B1
            ("achieve", "başarmak", "She achieved her goal.", "B1"), ("improve", "geliştirmek, iyileşmek", "I want to improve my English.", "B1"),
            ("opinion", "fikir, görüş", "In my opinion, it is a good idea.", "B1"), ("advice", "tavsiye", "Thanks for your advice.", "B1"),
            ("experience", "deneyim", "He has a lot of experience.", "B1"), ("environment", "çevre", "We must protect the environment.", "B1"),
            ("avoid", "kaçınmak", "Try to avoid sugar.", "B1"), ("suggest", "önermek", "I suggest we leave early.", "B1"),
            ("realize", "fark etmek", "I realized I forgot my keys.", "B1"), ("manage", "başarmak, yönetmek", "She managed to finish on time.", "B1"),
            ("benefit", "fayda, yarar", "Exercise has many benefits.", "B1"), ("challenge", "zorluk, meydan okuma", "Learning a language is a challenge.", "B1"),
            ("reliable", "güvenilir", "He is a reliable friend.", "B1"), ("recently", "son zamanlarda", "I have recently moved here.", "B1"),
            ("common", "yaygın, ortak", "This is a common mistake.", "B1"), ("require", "gerektirmek", "The job requires experience.", "B1"),
            ("provide", "sağlamak", "The hotel provides free breakfast.", "B1"), ("develop", "geliştirmek, gelişmek", "They develop mobile apps.", "B1"),
            ("compare", "karşılaştırmak", "Let's compare the two options.", "B1"), ("depend", "bağlı olmak", "It depends on the weather.", "B1"),
        ]
        return raw.map { VocabWord(en: $0.0, tr: $0.1, example: $0.2, level: $0.3) }
    }()
}
