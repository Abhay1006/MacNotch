import Foundation
import Combine

class QuotesManager: ObservableObject {
    @Published var currentQuote: String = ""
    
    private let quotes = [
        "It gets easier, if you do it every day it gets easier every day, the hard part is to do it every day.",
        "Youngest you will ever be is today.",
        "Don't try to surpass your limits but try to push them higher.",
        "I am build upon the small things I do everyday and the end results are no more than a byproduct of that.",
        "He who would climb the ladder must begin at the bottom.",
        "A dream is not what you see sleeping, a dream is what doesn’t let you sleep.",
        "You will never regret doing hard things.",
        "Sometimes greatest cause of your sadness is only you.",
        "Failure is not the opposite of success, it is the part of it.",
        "Pain is the only true feeling because you can’t fake it.",
        "You can’t see the future/top/goal, but you can see the next step.",
        "Mistakes done ones are mistakes, but mistake done twice is a habit",
        "There is only one rule in love: bring happiness to those you love.",
        "Life is unfair.",
        "In life you will never get a hater that is doing better than you.",
        "Sometimes when you are in dark place, you think you are burried, but you are planted.",
        "Love is death of duty.",
        "No risk no story",
        "When you are winning, you are not as good as you think you are. When you are loosing, you are not bad as you think you are.",
        "Extreme justice is extreme injustice.",
        "Those who cannot remember the past are condemned to repeat it.",
        "Stop complaining about the results you didn’t get from the work you didn’t put in. The only way you get more successful from most of the people is to do something most people aren’t willing to do.",
        "Habits become second nature.",
        "The Curse of Knowledge: The more familiar you become with an idea the worse you become at explaining it to others, because you forget what it's like to not know it, and therefore what needs to be explained to understand it.",
        "Fortune favours the bold.",
        "In life you don’t have to be more right, just try to be less wrong.",
        "There is only one good, knowledge, and only one evil, ignorance.",
        "It’s so easy to be great nowadays, because most of the world is weak.",
        "The success you are looking for is in the work you are avoiding.",
        "To work you have the right, but not to the fruits thereof.",
        "If you feel like u're loosing everything, remember, tree lose their leaves every year , yet they still stand tall and wait for better days to come.",
        "If you don’t fail you are not even trying.",
        "To get something you never had, you have to do something you never did.",
        "Discipline is doing what you hate to do, but do it like you love it.",
        "The difference between a noob and a master is that a master has failed more times than a noob had tried.",
        "If you do what you always did You will get what you always got",
        "wanna know how long it takes to get over disappointment? As long as you decide it takes.",
        "The heaviest thing in the world isn’t iron or gold, it’s an unmade decision.",
        "When you reach the peak, you realise the mountain wasn’t the obstacle…..you were",
        "Early to rise early to bed make a man healthy but socially dead",
        "In a war of ego the loser always wins",
        "When blind see the world for the first time , he throws away the same stick which had helped him at bad time",
        "We need to be reminded more than we need to be taught",
        "Any person capable of angering you becomes your master.",
        "Take a bigger bite, anything worth doing is worth overdoing",
        "Bura dekhne me nikla, bura na milyo koi, jab apne aap ko dekha to musse bura na koi",
        "Nature has no justice",
        "You never teach swimming to a drowning person",
        "Cage is cage be it made up of iron or gold",
        "How can you be late in life when it’s your life",
        "Kill the monster before it starts telling you his story, otherwise you will start loving him"
    ]
    
    init() {
        selectNewQuote()
    }
    
    func selectNewQuote() {
        var availableQuotes = quotes
        
        // Dynamically load quotes from Obsidian Vault "Quotes and ideas.md" if available
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let obsidianQuotesPath = "\(home)/Documents/Obsidian Vault/Quotes and ideas.md"
        
        if let content = try? String(contentsOfFile: obsidianQuotesPath, encoding: .utf8) {
            let lines = content.components(separatedBy: .newlines)
            var obsidianQuotes: [String] = []
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                var qText = ""
                if trimmed.hasPrefix("- [ ]") || trimmed.hasPrefix("- [x]") || trimmed.hasPrefix("- [X]") {
                    qText = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                } else if trimmed.hasPrefix("- ") {
                    qText = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                }
                if !qText.isEmpty && qText.count > 3 {
                    obsidianQuotes.append(qText)
                }
            }
            if !obsidianQuotes.isEmpty {
                availableQuotes = obsidianQuotes
            }
        }
        
        // Prevent showing the exact same quote twice in a row if there are multiple quotes
        var newQuote = availableQuotes.randomElement() ?? "Stay motivated!"
        if availableQuotes.count > 1 {
            while newQuote == currentQuote {
                newQuote = availableQuotes.randomElement() ?? "Stay motivated!"
            }
        }
        currentQuote = newQuote
    }
}
