package spark.jobserver

import akka.actor.{ActorRef, ActorSystem, Props}
import akka.testkit.{ImplicitSender, TestKit}
import org.scalatest.{BeforeAndAfter, BeforeAndAfterAll, FunSpecLike, Matchers}
import java.io.File
import java.nio.file.Files

import spark.jobserver.common.akka
import spark.jobserver.common.akka.AkkaTestUtils
import spark.jobserver.io.DataFileDAO

object DataManagerActorSpec {
  val system = ActorSystem("test")
}

class DataManagerActorSpec extends TestKit(DataManagerActorSpec.system) with ImplicitSender
    with FunSpecLike with Matchers with BeforeAndAfter with BeforeAndAfterAll {

  import com.typesafe.config._
  import DataManagerActor._

  private val bytes = Array[Byte](0, 1, 2)
  private val tmpDir = Files.createTempDirectory("ut")
  private val config = ConfigFactory.empty().withValue("spark.jobserver.datadao.rootdir",
    ConfigValueFactory.fromAnyRef(tmpDir.toString))

  override def afterAll() {
    dao.shutdown()
    AkkaTestUtils.shutdownAndWait(actor)
    akka.AkkaTestUtils.shutdownAndWait(DataManagerActorSpec.system)
    Files.delete(tmpDir.resolve(DataFileDAO.META_DATA_FILE_NAME))
    Files.delete(tmpDir)
  }

  val dao: DataFileDAO = new DataFileDAO(config)
  val actor: ActorRef = system.actorOf(Props(classOf[DataManagerActor], dao), "data-manager")

  describe("DataManagerActor") {
    it("should store, list and delete tmp data file") {
      val fileNamePrefix = System.currentTimeMillis + "tmpFile"

      actor ! StoreData(fileNamePrefix, bytes)
      val fileName = expectMsgPF() {
        case Stored(msg) => msg
      }
      fileName should startWith (fileNamePrefix)

      dao.listFiles.exists(f => f.contains(fileName)) should be(true)
      actor ! DeleteData(fileName)
      expectMsg(Deleted)
      dao.listFiles.exists(f => f.contains(fileName)) should be(false)
    }

    it("should list data files") {
      actor ! ListData

      val storedFiles = expectMsgPF() {
        case files => files
      }

      storedFiles should equal(dao.listFiles)
      dao.listFiles should equal(Set())
    }

    it("should store, list and delete several files") {
      val storedFiles = (for (ix <- 1 to 11; fileName = System.currentTimeMillis + "tmpFile" + ix) yield {
        actor ! StoreData(fileName, bytes)
        expectMsgPF() {
          case Stored(msg) => msg
        }
      }).toSet
      dao.listFiles should equal(storedFiles)
      dao.listFiles should not equal(Set())

      actor ! ListData
      val actorList = expectMsgPF() {
        case files => files
      }
      actorList should equal(storedFiles)

      storedFiles foreach (fn => {
        actor ! DeleteData(new File(fn).getName)
        expectMsg(Deleted)
      })
      dao.listFiles should equal(Set())
    }

    it("should return an error on unknown files") {
      actor ! DeleteData("unknown-file")
      expectMsg(Error)
    }

    it("should return an error if file was already removed") {
      val fileNamePrefix = System.currentTimeMillis + "tmpFile"
      actor ! StoreData(fileNamePrefix, bytes)
      val fileName = expectMsgPF() {
        case Stored(msg) => msg
      }

      actor ! DeleteData(fileName)
      expectMsg(Deleted)

      actor ! DeleteData(fileName)
      expectMsg(Error)
    }
  }
}
