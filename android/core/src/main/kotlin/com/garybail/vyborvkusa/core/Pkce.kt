package com.garybail.vyborvkusa.core

import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64

/** PKCE для входа через VK ID / Яндекс ID: случайный code_verifier и его SHA-256 (code_challenge). */
object Pkce {
    private val random = SecureRandom()
    private val encoder = Base64.getUrlEncoder().withoutPadding()

    fun randomToken(bytes: Int = 32): String = encoder.encodeToString(ByteArray(bytes).also(random::nextBytes))

    fun challenge(verifier: String): String =
        encoder.encodeToString(MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray(Charsets.US_ASCII)))
}
