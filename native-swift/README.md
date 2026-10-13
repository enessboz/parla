# English Practice (macOS)

Yerel LLM (Ollama) + Apple Speech ile İngilizce konuşma pratiği. Native SwiftUI, macOS 14+.

## Kurulum
1. `brew install ollama && ollama serve` (ayrı terminalde), sonra `ollama pull gemma3:4b`
2. Xcode Command Line Tools: `xcode-select --install`
3. `./build_app.sh && open EnglishPractice.app`
4. İlk açılışta mikrofon ve konuşma tanıma izinlerini ver. Model/adres: Ayarlar (⌘,).

## Özellikler
- Yazarak veya konuşarak sohbet; her mesajda hata düzeltme + Türkçe açıklama
- Telaffuz: Apple Speech'in kelime güven skoru düşükse kelime turuncu işaretlenir
- Hatalar kategoriye göre SwiftData'da birikir
- Sık yapılan hata kategorisinden LLM ile kişisel ders + alıştırma üretilir
