public class Uppgift12a_1 {
   public static void main(String[] args) {

      double pi = 0;
      double denominator = 1;

      for (int i = 0; i < 500; i++) {

         if (i % 2 == 0) {
            pi = pi + (1 / denominator);
         } else {
            pi = pi - (1 / denominator);
         }
         denominator = denominator + 2;
      }
      pi = pi * 4;
      System.out.println(pi);
   }
 }
