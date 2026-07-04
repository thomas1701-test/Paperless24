package de.tedi.paperless.repository

import de.tedi.paperless.data.local.AccountDao
import de.tedi.paperless.data.local.AccountEntity
import de.tedi.paperless.data.local.SecureTokenStore
import de.tedi.paperless.network.RetrofitFactory
import de.tedi.paperless.network.TokenRequest
import javax.inject.Inject
import retrofit2.HttpException

sealed class LoginResult {
    data class Success(val accountId: Long) : LoginResult()
    object OtpRequired : LoginResult()
    data class Failure(val message: String) : LoginResult()
}

class AuthRepository @Inject constructor(
    private val accountDao: AccountDao,
    private val tokenStore: SecureTokenStore
) {
    suspend fun login(serverUrl: String, username: String, password: String, otp: String? = null): LoginResult {
        return try {
            val service = RetrofitFactory.createUnauthenticated(serverUrl)
            val response = service.fetchToken(TokenRequest(username, password, otp))
            accountDao.clearActive()
            val id = accountDao.insert(
                AccountEntity(serverUrl = serverUrl, username = username, isActive = true)
            )
            tokenStore.saveToken(id, response.token)
            LoginResult.Success(id)
        } catch (e: HttpException) {
            val body = e.response()?.errorBody()?.string().orEmpty().lowercase()
            val otpKeywords = listOf("otp", "totp", "mfa", "2fa", "one-time")
            if (otp == null && otpKeywords.any { body.contains(it) }) {
                LoginResult.OtpRequired
            } else {
                LoginResult.Failure("Anmeldung fehlgeschlagen (${e.code()})")
            }
        } catch (e: Exception) {
            LoginResult.Failure(e.message ?: "Unbekannter Fehler")
        }
    }

    suspend fun switchAccount(accountId: Long) {
        accountDao.clearActive()
        accountDao.setActive(accountId)
    }

    suspend fun removeAccount(account: AccountEntity) {
        tokenStore.removeToken(account.id)
        accountDao.delete(account)
    }
}
