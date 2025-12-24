//
//  OpenAIClient.swift
//  TypeFixPrototype
//
//  Handles communication with the OpenAI API for text correction.
//  Supports two correction modes:
//  - Basic: Grammar and spelling correction only
//  - Fact Checking: Grammar, spelling, and factual accuracy verification
//
//  Uses different GPT models based on the selected mode to optimize
//  performance and cost. The API key must be configured before use.
//

import Foundation

final class OpenAIClient {
    
    private var apiKey: String? {
        return KeychainManager.getAPIKey()
    }
    
    private let endpoint = "https://api.openai.com/v1/chat/completions"
    private let basicModel = "gpt-4.1-nano-2025-04-14"
    private let factCheckModel = "gpt-5-nano-2025-08-07" 
    
    var correctionMode: CorrectionMode = .basic {
        didSet {
            onLog?("Correction mode changed to: \(correctionMode == .basic ? "Basic" : "Fact Checking")")
        }
    }
    
    var onLog: ((String) -> Void)?
    
    private var currentModel: String {
        return correctionMode == .basic ? basicModel : factCheckModel
    }
    
    func correctText(_ text: String, completion: @escaping (String?, Error?) -> Void) {
        guard let apiKey = apiKey else {
            let error = NSError(domain: "OpenAIClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Please add your OpenAI API Key from the menu bar"])
            onLog?("API Key not set. Please add your API key from the menu bar.")
            completion(nil, error)
            return
        }
        
        guard let url = URL(string: endpoint) else {
            onLog?("Invalid URL: \(endpoint)")
            completion(nil, NSError(domain: "OpenAIClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
            return
        }
        
        onLog?("Requesting correction for text: \"\(text)\"")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let systemPrompt: String
        if correctionMode == .fullFactChecking {
            systemPrompt = """
            You are a specialized text correction engine with comprehensive fact-checking capabilities. You will receive text that the user is currently typing. Your task is to return ONLY the corrected version of the text.
            
            CORRECTION TASKS:
            1. Fix grammar, spelling, and capitalization errors
            2. FACT-CHECK ALL factual claims in the text and correct any factual errors
            3. ensure the text makes sense in context and fix any contextual errors (e.g., "their" vs "there", "stationary" vs "stationery")
            
            FACT-CHECKING RULES:
            - Verify ANY factual claim made in the text, regardless of category (geography, history, science, current events, people, places, dates, definitions, relationships, etc.)
            - If you detect ANY factual error, replace the incorrect information with the correct fact
            - Use your knowledge to verify claims about locations, dates, names, definitions, relationships, properties, and any other factual statements
            - Example: "I'm going to SFO, it's in Vancouver" → "I'm going to SFO, it's in San Francisco"
            - Example: "The capital of France is London" → "The capital of France is Paris"
            - Example: "Einstein discovered gravity" → "Einstein developed the theory of relativity" (or correct based on context)
            - Example: "Water boils at 200 degrees" → "Water boils at 100 degrees Celsius"
            
            OUTPUT FORMAT:
            - Return ONLY the corrected text
            - Do not add quotes, prefixes, suffixes, or any conversational text
            - Do not add explanations or notes about what you changed
            - If the text is already correct (grammar, spelling, AND facts), return it exactly as is
            - Preserve the original meaning and tone
            """
        } else {
            systemPrompt = """
            You are a specialized text correction engine. You will receive text that the user is currently typing. Your task is to return ONLY the corrected version of the text.
            
            CORRECTION TASKS:
            1. Fix grammar, spelling, and capitalization errors
            2. Ensure the text makes sense in context and fix any contextual errors (e.g., "their" vs "there", "stationary" vs "stationery")
            
            OUTPUT FORMAT:
            - Return ONLY the corrected text
            - Do not add quotes, prefixes, suffixes, or any conversational text
            - Do not add explanations or notes about what you changed
            - If the text is already correct (grammar and spelling), return it exactly as is
            - Preserve the original meaning and tone
            """
        }
        
        let body: [String: Any] = [
            "model": currentModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": 1
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            // Log request summary (without full JSON)
            if let messages = body["messages"] as? [[String: Any]],
               let userMessage = messages.first(where: { ($0["role"] as? String) == "user" }),
               let content = userMessage["content"] as? String {
                onLog?("Sending to OpenAI (model: \(currentModel), text length: \(content.count) chars)")
            }
        } catch {
            onLog?("Failed to serialize request: \(error.localizedDescription)")
            completion(nil, error)
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                self.onLog?("Network error: \(error.localizedDescription)")
                completion(nil, error)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                self.onLog?("HTTP Status: \(httpResponse.statusCode)")
            }
            
            guard let data = data else {
                self.onLog?("No data received from OpenAI")
                completion(nil, NSError(domain: "OpenAIClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data"]))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                    let content = message["content"] as? String {
                    
                    let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.onLog?("Correction received: \"\(trimmedContent)\"")
                    completion(trimmedContent, nil)
                } else {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorObj = json["error"] as? [String: Any],
                       let message = errorObj["message"] as? String {
                        let errorType = errorObj["type"] as? String ?? "unknown"
                        let errorCode = errorObj["code"] as? String ?? "unknown"
                        self.onLog?("OpenAI API Error [\(errorType): \(errorCode)]: \(message)")
                        completion(nil, NSError(domain: "OpenAIClient", code: 400, userInfo: [NSLocalizedDescriptionKey: message]))
                    } else {
                        self.onLog?("Failed to parse response format - unexpected structure")
                        completion(nil, NSError(domain: "OpenAIClient", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"]))
                    }
                }
            } catch {
                self.onLog?("JSON parsing error: \(error.localizedDescription)")
                completion(nil, error)
            }
        }
        
        task.resume()
    }
}

