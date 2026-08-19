package app.juicr.flutter

internal class P2pGenerationOwnership {
    private val generationsByToken = linkedMapOf<String, MutableSet<Long>>()

    @Synchronized
    fun register(token: String, generation: Long) {
        require(token.isNotBlank())
        require(generation > 0L)
        generationsByToken.getOrPut(token) { linkedSetOf() }.add(generation)
    }

    @Synchronized
    fun owns(token: String, generation: Long): Boolean {
        return generationsByToken[token]?.contains(generation) == true
    }

    @Synchronized
    fun removeGeneration(generation: Long): Set<String> {
        if (generation <= 0L) return emptySet()
        return removeMatching { it == generation }
    }

    @Synchronized
    fun removeThrough(generation: Long): Set<String> {
        if (generation <= 0L) return emptySet()
        return removeMatching { it <= generation }
    }

    @Synchronized
    fun removeAll(): Set<String> {
        val tokens = generationsByToken.keys.toSet()
        generationsByToken.clear()
        return tokens
    }

    @Synchronized
    fun isEmpty(): Boolean = generationsByToken.isEmpty()

    private fun removeMatching(predicate: (Long) -> Boolean): Set<String> {
        val unownedTokens = linkedSetOf<String>()
        for ((token, generations) in generationsByToken.entries.toList()) {
            generations.removeAll(predicate)
            if (generations.isEmpty()) {
                generationsByToken.remove(token)
                unownedTokens.add(token)
            }
        }
        return unownedTokens
    }
}
