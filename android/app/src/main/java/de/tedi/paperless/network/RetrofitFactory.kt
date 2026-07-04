package de.tedi.paperless.network

import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import retrofit2.Retrofit
import retrofit2.converter.moshi.MoshiConverterFactory

object RetrofitFactory {
    fun create(serverUrl: String, token: String): PaperlessService {
        val cleanUrl = serverUrl.trimEnd('/').let {
            if (it.startsWith("http")) it else "http://$it"
        }
        val authInterceptor = Interceptor { chain ->
            val request = chain.request().newBuilder()
                .addHeader("Authorization", "Token $token")
                .build()
            chain.proceed(request)
        }
        val client = OkHttpClient.Builder()
            .addInterceptor(authInterceptor)
            .build()
        val moshi = Moshi.Builder().add(KotlinJsonAdapterFactory()).build()
        return Retrofit.Builder()
            .baseUrl("$cleanUrl/")
            .client(client)
            .addConverterFactory(MoshiConverterFactory.create(moshi))
            .build()
            .create(PaperlessService::class.java)
    }

    fun createUnauthenticated(serverUrl: String): PaperlessService {
        val cleanUrl = serverUrl.trimEnd('/').let {
            if (it.startsWith("http")) it else "http://$it"
        }
        val moshi = Moshi.Builder().add(KotlinJsonAdapterFactory()).build()
        return Retrofit.Builder()
            .baseUrl("$cleanUrl/")
            .addConverterFactory(MoshiConverterFactory.create(moshi))
            .build()
            .create(PaperlessService::class.java)
    }
}
