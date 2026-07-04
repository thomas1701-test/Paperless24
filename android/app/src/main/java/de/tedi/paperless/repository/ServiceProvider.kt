package de.tedi.paperless.repository

import de.tedi.paperless.data.local.AccountDao
import de.tedi.paperless.data.local.SecureTokenStore
import de.tedi.paperless.network.PaperlessService
import de.tedi.paperless.network.RetrofitFactory
import javax.inject.Inject

class ServiceProvider @Inject constructor(
    private val accountDao: AccountDao,
    private val tokenStore: SecureTokenStore
) {
    suspend fun current(): PaperlessService? {
        val account = accountDao.getActive() ?: return null
        val token = tokenStore.getToken(account.id) ?: return null
        return RetrofitFactory.create(account.serverUrl, token)
    }
}
