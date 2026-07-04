package de.tedi.paperless.viewmodel

import app.cash.turbine.test
import de.tedi.paperless.network.model.Tag
import de.tedi.paperless.repository.MetadataRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.mockito.kotlin.mock
import org.mockito.kotlin.whenever
import kotlin.test.assertEquals

@OptIn(ExperimentalCoroutinesApi::class)
class MetadataViewModelTest {
    private val testDispatcher = StandardTestDispatcher()

    @Before
    fun setUpDispatcher() { Dispatchers.setMain(testDispatcher) }

    @After
    fun tearDownDispatcher() { Dispatchers.resetMain() }

    @Test
    fun `createTag appends new tag to list`() = runTest {
        val repo: MetadataRepository = mock()
        whenever(repo.getTags()).thenReturn(emptyList())
        whenever(repo.createTag("Steuer")).thenReturn(Tag(id = 1, name = "Steuer"))
        val vm = MetadataViewModel(repo)

        vm.state.test {
            assertEquals(emptyList(), awaitItem().tags)
            // loadTags() resolves to the same emptyList() value already held by the
            // StateFlow, so MutableStateFlow's conflation of equal values means no new
            // emission is produced here (StateFlow only emits on distinct-until-changed).
            vm.loadTags()
            vm.createTag("Steuer")
            assertEquals(listOf(Tag(id = 1, name = "Steuer")), awaitItem().tags)
        }
    }
}
